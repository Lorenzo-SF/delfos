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
    cfg = Delfos.Config.Manager.llm()
    use_case = Keyword.get(opts, :use_case, :query)
    provider = Keyword.get(opts, :provider, cfg[:provider])

    {url, model, max_tokens} = resolve_endpoint(cfg, use_case, opts)

    # Prefer Candil for OpenAI-compatible providers when available.
    if provider != :anthropic and Delfos.LLM.CandilBridge.available?() do
      Delfos.LLM.CandilBridge.chat(messages, cfg, opts)
    else
      case provider do
        :anthropic -> chat_anthropic(messages, model, max_tokens, cfg, url)
        _ -> chat_openai(messages, model, max_tokens, cfg, url)
      end
    end
  end

  defp resolve_endpoint(cfg, use_case, opts) do
    # max_tokens: priority to explicit opts, then per use case
    max_tokens =
      Keyword.get(opts, :max_tokens) ||
        case use_case do
          :summarize -> cfg[:summarize_max_tokens] || 180
          :explain -> cfg[:explain_max_tokens] || 600
          :query -> cfg[:query_max_tokens] || 512
          _ -> cfg[:query_max_tokens] || 512
        end

    # For explain and query, use the thinker model when configured and available
    use_thinker =
      use_case in [:explain, :query] and
        cfg[:use_thinker_for_query] == true and
        cfg[:thinker_url] not in [nil, ""]

    if use_thinker do
      {cfg[:thinker_url], cfg[:thinker_model], max_tokens}
    else
      {cfg[:url], cfg[:model], max_tokens}
    end
  end

  # ---------------------------------------------------------------------------
  # Embeddings
  # ---------------------------------------------------------------------------

  def embed(text, opts \\ []) do
    cfg = Delfos.Config.Manager.embedding()
    provider = Keyword.get(opts, :provider, cfg[:provider])

    if provider != :anthropic and Delfos.LLM.CandilBridge.available?() do
      case Delfos.LLM.CandilBridge.embed(text, cfg) do
        {:ok, [vec | _]} -> {:ok, vec}
        {:ok, []} -> {:error, "empty embedding"}
        err -> err
      end
    else
      case provider do
        :openai -> embed_openai([text], cfg) |> unwrap_first()
        :anthropic -> {:error, "Anthropic does not support embeddings. Use provider=openai or local."}
        _ -> embed_local(text, cfg)
      end
    end
  end

  def embed_batch(texts, opts \\ []) do
    cfg = Delfos.Config.Manager.embedding()
    provider = Keyword.get(opts, :provider, cfg[:provider])

    if provider != :anthropic and Delfos.LLM.CandilBridge.available?() do
      Delfos.LLM.CandilBridge.embed_batch(texts, cfg)
    else
      batch_size = cfg[:batch_size] || 48

      case provider do
        :openai ->
          texts
          |> Enum.chunk_every(batch_size)
          |> Enum.flat_map(fn batch ->
            case embed_openai(batch, cfg) do
              {:ok, vecs} -> vecs
              _ -> Enum.map(batch, fn _ -> nil end)
            end
          end)

        :anthropic ->
          Logger.warning("Anthropic does not support embeddings. Change embedding.provider.")
          Enum.map(texts, fn _ -> nil end)

        _ ->
          texts
          |> Enum.chunk_every(batch_size)
          |> Enum.flat_map(fn batch ->
            case embed_local_batch(batch, cfg) do
              {:ok, vecs} -> vecs
              _ -> Enum.map(batch, fn _ -> nil end)
            end
          end)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Implementaciones OpenAI / Local
  # ---------------------------------------------------------------------------

  defp chat_openai(messages, model, max_tokens, cfg, url) do
    Req.post("#{url}/v1/chat/completions",
      auth: {:bearer, cfg[:api_key]},
      json: %{model: model, messages: messages, max_tokens: max_tokens, stream: false},
      receive_timeout: cfg[:timeout_ms]
    )
    |> handle_openai_chat()
  end

  defp embed_local(text, cfg) do
    case Req.post("#{cfg[:url]}/v1/embeddings",
           auth: {:bearer, cfg[:api_key]},
           json: %{model: cfg[:model], input: String.slice(text, 0, 8000)},
           receive_timeout: cfg[:timeout_ms]
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, get_in(body, ["data", Access.at(0), "embedding"])}

      {:ok, %{status: s, body: b}} ->
        {:error, "HTTP #{s}: #{inspect(b)}"}

      {:error, r} ->
        {:error, r}
    end
  end

  defp embed_local_batch(texts, cfg) do
    case Req.post("#{cfg[:url]}/v1/embeddings",
           auth: {:bearer, cfg[:api_key]},
           json: %{model: cfg[:model], input: texts},
           receive_timeout: cfg[:timeout_ms]
         ) do
      {:ok, %{status: 200, body: body}} ->
        vecs = body["data"] |> Enum.sort_by(& &1["index"]) |> Enum.map(& &1["embedding"])
        {:ok, vecs}

      {:ok, %{status: s, body: b}} ->
        {:error, "HTTP #{s}: #{inspect(b)}"}

      {:error, r} ->
        {:error, r}
    end
  end

  defp embed_openai(texts, cfg) do
    case Req.post("#{cfg[:url]}/v1/embeddings",
           auth: {:bearer, cfg[:api_key]},
           json: %{model: cfg[:model], input: texts},
           receive_timeout: cfg[:timeout_ms]
         ) do
      {:ok, %{status: 200, body: body}} ->
        vecs = body["data"] |> Enum.sort_by(& &1["index"]) |> Enum.map(& &1["embedding"])
        {:ok, vecs}

      {:ok, %{status: s, body: b}} ->
        {:error, "HTTP #{s}: #{inspect(b)}"}

      {:error, r} ->
        {:error, r}
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

    Req.post("#{url}/v1/messages",
      headers: [
        {"x-api-key", cfg[:api_key]},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ],
      json: body,
      receive_timeout: cfg[:timeout_ms]
    )
    |> handle_anthropic()
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
  defp handle_anthropic({:error, r}), do: {:error, r}

  defp handle_openai_chat({:ok, %{status: 200, body: body}}) do
    {:ok, get_in(body, ["choices", Access.at(0), "message", "content"])}
  end

  defp handle_openai_chat({:ok, %{status: s, body: b}}), do: {:error, "HTTP #{s}: #{inspect(b)}"}
  defp handle_openai_chat({:error, r}), do: {:error, r}

  defp unwrap_first({:ok, [vec | _]}), do: {:ok, vec}
  defp unwrap_first({:ok, []}), do: {:error, "empty embedding"}
  defp unwrap_first(err), do: err
end
