defmodule Delfos.LLM.Client do
  @moduledoc """
  Multi-provider HTTP client with per-use-case routing.

  Uses ONE model (configured via `[llm]`) for all chat tasks:
    - :summarize  → uses the [summarize] section if present, else falls
                    back to `[llm]` (with summarize_max_tokens / max_tokens).
    - :explain    → uses [llm] with explain_max_tokens.
    - :query      → uses [llm] with query_max_tokens.

  Supports providers: :local (OpenAI-compat), :openai, :anthropic.

  When `Candil` is loaded as an optional dependency, OpenAI-compatible
  chat + embedding calls go through `Delfos.LLM.CandilBridge` which
  delegates to `Candil.chat/4` and `Candil.embed/4`. Anthropic calls
  stay on the direct path because Candil does not yet model that
  provider.

  ## Resilience (added in v2.4.0)

  Anthropic chat calls in `chat_anthropic/5` are protected by a
  defense-in-depth combination:

      CircuitBreaker.call(breaker, fn -> ... end)   # system protection
      |> Apero.Retry.with(max_attempts: 3, ...)    # transient 5xx/429

  The breaker is registered per-host via `Delfos.LLM.Breakers` and opens
  after 5 consecutive failures (60s timeout). When the breaker is open,
  calls fail-fast with `:circuit_open` — protecting the upstream LLM
  from cascading failure storms. The retry layer provides the standard
  3-attempt backoff for transient errors. See
  `candil/lib/candil/http.ex` for the canonical pattern.
  """

  require Logger

  alias Arrea.CircuitBreaker
  alias Delfos.LLM.Breakers

  # ---------------------------------------------------------------------------
  # Chat
  # ---------------------------------------------------------------------------

  @doc """
  Sends a chat request to the LLM.
  `use_case` can be :summarize | :explain | :query (controls max_tokens and model).
  """
  def chat(messages, opts \\ []) do
    use_case = Keyword.get(opts, :use_case, :query)
    cfg = resolve_cfg(use_case)
    provider = Keyword.get(opts, :provider, cfg[:provider])

    {url, model, max_tokens} = resolve_endpoint(cfg, use_case, opts)

    # Candil es una dependencia permanente — siempre está disponible.
    # Para Anthropic usamos el path directo porque Candil aún no modela
    # ese provider; para todo lo demás, CandilBridge da mejor integración
    # (registry de modelos, engines, etc.).
    if provider == :anthropic do
      chat_anthropic(messages, model, max_tokens, cfg, url)
    else
      Delfos.LLM.CandilBridge.chat(messages, cfg, opts)
    end
  end

  @doc false
  def resolve_cfg(:summarize) do
    case Delfos.Config.Manager.summarize() do
      nil -> Delfos.Config.Manager.llm()
      cfg -> cfg
    end
  end

  def resolve_cfg(_), do: Delfos.Config.Manager.llm()

  defp resolve_endpoint(cfg, use_case, opts) do
    # max_tokens: priority to explicit opts, then per use case.
    # cfg[:summarize_max_tokens] is a backward-compat fallback for
    # configs that still have it inside [llm] rather than [summarize].
    max_tokens =
      Keyword.get(opts, :max_tokens) ||
        case use_case do
          :summarize -> cfg[:max_tokens] || cfg[:summarize_max_tokens] || 400
          :explain -> cfg[:explain_max_tokens] || 600
          :query -> cfg[:query_max_tokens] || 512
          _ -> cfg[:query_max_tokens] || 512
        end

    # Single LLM endpoint — used for chat, query, explain, summarize.
    # No thinker: there is one model, configured once via `[llm]` (or
    # `[summarize]` for the optional summarizer override).
    {cfg[:url], cfg[:model], max_tokens}
  end

  # ---------------------------------------------------------------------------
  # Embeddings
  # ---------------------------------------------------------------------------

  def embed(text, opts \\ []) do
    cfg = Delfos.Config.Manager.embedding()
    provider = Keyword.get(opts, :provider, cfg[:provider])

    if provider == :anthropic do
      {:error, "Anthropic does not support embeddings. Use provider=openai or local."}
    else
      case Delfos.LLM.CandilBridge.embed(text, cfg) do
        {:ok, [vec | _]} -> {:ok, vec}
        {:ok, []} -> {:error, "empty embedding"}
        err -> err
      end
    end
  end

  def embed_batch(texts, opts \\ []) do
    cfg = Delfos.Config.Manager.embedding()
    provider = Keyword.get(opts, :provider, cfg[:provider])

    if provider == :anthropic do
      Logger.warning("Anthropic does not support embeddings. Change embedding.provider.")
      Enum.map(texts, fn _ -> nil end)
    else
      Delfos.LLM.CandilBridge.embed_batch(texts, cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # Anthropic /v1/messages
  # ---------------------------------------------------------------------------

  defp chat_anthropic(messages, model, max_tokens, cfg, url) do
    {system_prompt, user_messages} = extract_system(messages)

    body =
      %{model: model, max_tokens: max_tokens, messages: user_messages}
      |> then(fn b -> if system_prompt, do: Map.put(b, :system, system_prompt), else: b end)

    breaker = Breakers.name_for(url)
    Breakers.ensure_running(breaker)

    # Retry wraps the breaker. Each individual attempt is itself protected
    # by the breaker, which opens after 5 consecutive failures and blocks
    # subsequent calls for 60s. The retry handles transient 5xx/429 with
    # backoff.
    fn ->
      CircuitBreaker.call(breaker, fn ->
        Apero.Http.post(
          "#{url}/v1/messages",
          body,
          [
            {"x-api-key", cfg[:api_key]},
            {"anthropic-version", "2023-06-01"},
            {"content-type", "application/json"}
          ],
          receive_timeout: cfg[:timeout_ms]
        )
        |> handle_anthropic()
      end)
      |> case do
        {:ok, _} = ok ->
          ok

        {:error, :circuit_open} ->
          {:error, "circuit_open: LLM endpoint unreachable"}

        {:error, :execution_failed} ->
          {:error, "execution_failed: LLM request raised"}

        other ->
          other
      end
    end
    |> Apero.Retry.with(
      max_attempts: 3,
      base_delay: 1_000,
      max_delay: 10_000,
      retry_on: fn
        {:error, reason} when is_binary(reason) ->
          String.starts_with?(reason, "HTTP 5") or
            String.starts_with?(reason, "HTTP 429") or
            reason == "circuit_open: LLM endpoint unreachable" or
            reason == "execution_failed: LLM request raised"

        _ ->
          false
      end
    )
  end

  defp extract_system(messages) do
    system =
      Enum.find_value(messages, fn m ->
        if (m[:role] || m["role"]) == "system", do: m[:content] || m["content"]
      end)

    user_msgs = Enum.reject(messages, fn m -> (m[:role] || m["role"]) == "system" end)
    {system, user_msgs}
  end

  defp handle_anthropic({:ok, %{status: 200, body: body}}) do
    case get_in(body, ["content"]) |> List.first() do
      %{"type" => "text", "text" => text} -> {:ok, text}
      _ -> {:error, "Anthropic: empty response"}
    end
  end

  defp handle_anthropic({:ok, %{status: s, body: b}}), do: {:error, "HTTP #{s}: #{inspect(b)}"}

  defp handle_anthropic({:error, %Apero.Http.Error{reason: reason}}) do
    {:error, inspect(reason)}
  end

  defp handle_anthropic({:error, r}), do: {:error, r}
end
