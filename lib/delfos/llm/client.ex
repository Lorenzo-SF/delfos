defmodule Delfos.LLM.Client do
  @moduledoc """
  Multi-provider HTTP client with per-use-case routing.

  Uses two distinct models depending on the task type:
    - :summarize  → fast model (Coder-3B) with short max_tokens
    - :explain    → higher-capacity model (thinker) if configured
    - :query      → thinker if use_thinker_for_query=true, else base model

  Supports providers: :local (OpenAI-compat), :openai, :anthropic.

  When `Candil` is loaded as an optional dependency, OpenAI-compatible
  chat + embedding calls go through `Delfos.LLM.CandilBridge` which
  delegates to `Candil.chat/4` and `Candil.embed/4`. Anthropic calls
  stay on the direct path because Candil does not yet model that
  provider.
  """

  require Logger

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
    max_tokens =
      Keyword.get(opts, :max_tokens) ||
        case use_case do
          :summarize -> cfg[:max_tokens] || cfg[:summarize_max_tokens] || 400
          :explain -> cfg[:explain_max_tokens] || 600
          :query -> cfg[:query_max_tokens] || 512
          _ -> cfg[:query_max_tokens] || 512
        end

    # Delfos no gestiona un segundo "thinker" endpoint: usa el modelo
    # base configurado para todo. (Antes había thinker_url/thinker_model;
    # si aparece un cfg legacy con esas claves, se ignoran.)
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
      # FE-3: lookup in cache; only send misses to the provider.
      # Preserves input order: returns vec/nil per text in original order.
      {cached, uncached_idx, uncached_texts} = partition_by_cache(texts)
      results_by_idx = Map.new(cached, fn {idx, vec} -> {idx, vec} end)

      uncached_results =
        if uncached_texts == [] do
          %{}
        else
          Delfos.LLM.CandilBridge.embed_batch(uncached_texts, cfg)
          |> cache_and_index(uncached_texts)
        end

      # Merge: hit → cached vec; miss → from provider; nil → still nil
      Enum.map(0..(length(texts) - 1), fn idx ->
        Map.get_lazy(results_by_idx, idx, fn ->
          Enum.find_value(uncached_results, fn {u_idx, vec} ->
            if Enum.at(uncached_idx, u_idx) == idx, do: vec
          end)
        end)
      end)
    end
  end

  # Splits texts into (cached [{idx, vec}], uncached_idx, uncached_texts).
  defp partition_by_cache(texts) do
    texts
    |> Enum.with_index()
    |> Enum.reduce({[], [], []}, fn {text, idx}, {cached, u_idx, u_texts} ->
      case Delfos.Embeddings.Cache.lookup(text) do
        {:ok, vec} -> {[{idx, vec} | cached], u_idx, u_texts}
        :miss -> {cached, [idx | u_idx], [text | u_texts]}
      end
    end)
    |> then(fn {cached, u_idx, u_texts} ->
      {cached, Enum.reverse(u_idx), Enum.reverse(u_texts)}
    end)
  end

  # Populates cache for the newly-fetched embeddings and returns
  # the list in the same order as the input.
  defp cache_and_index(results, uncached_texts) do
    pairs =
      uncached_texts
      |> Enum.zip(results)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    Delfos.Embeddings.Cache.fill_misses(pairs)

    pairs
    |> Enum.with_index()
    |> Enum.map(fn {{_text, vec}, i} -> {i, vec} end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Anthropic /v1/messages
  # ---------------------------------------------------------------------------

  defp chat_anthropic(messages, model, max_tokens, cfg, url) do
    {system_prompt, user_messages} = extract_system(messages)

    body =
      %{model: model, max_tokens: max_tokens, messages: user_messages}
      |> then(fn b -> if system_prompt, do: Map.put(b, :system, system_prompt), else: b end)

    request_fn = fn ->
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
    end

    request_fn
    |> Apero.Retry.with(
      max_attempts: 3,
      base_delay: 1_000,
      max_delay: 10_000,
      retry_on: fn
        {:error, reason} when is_binary(reason) ->
          String.starts_with?(reason, "HTTP 5") or String.starts_with?(reason, "HTTP 429")

        {:error, _} ->
          true

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
