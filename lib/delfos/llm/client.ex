defmodule Delfos.LLM.Client do
  @moduledoc """
  Cliente HTTP multi-proveedor con enrutamiento por caso de uso.

  Usa dos modelos distintos según el tipo de tarea:
    - :summarize  → modelo rápido (Coder-3B) con max_tokens cortos
    - :explain    → modelo de mayor capacidad (thinker) si está configurado
    - :query      → thinker si use_thinker_for_query=true, sino modelo base

  Soporta proveedores: :local (OpenAI-compat), :openai, :anthropic
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Chat
  # ---------------------------------------------------------------------------

  @doc """
  Envía un request de chat al LLM.
  `use_case` puede ser :summarize | :explain | :query (controla max_tokens y modelo).
  """
  def chat(messages, opts \\ []) do
    cfg = Delfos.Config.Manager.llm()
    use_case = Keyword.get(opts, :use_case, :query)
    provider = Keyword.get(opts, :provider, cfg[:provider])

    {url, model, max_tokens} = resolve_endpoint(cfg, use_case, opts)

    case provider do
      :anthropic -> chat_anthropic(messages, model, max_tokens, cfg, url)
      _ -> chat_openai(messages, model, max_tokens, cfg, url)
    end
  end

  defp resolve_endpoint(cfg, use_case, opts) do
    # max_tokens: prioridad a opts explícito, luego por caso de uso
    max_tokens =
      Keyword.get(opts, :max_tokens) ||
        case use_case do
          :summarize -> cfg[:summarize_max_tokens] || 180
          :explain -> cfg[:explain_max_tokens] || 600
          :query -> cfg[:query_max_tokens] || 512
          _ -> cfg[:query_max_tokens] || 512
        end

    # Para explain y query, usar thinker si está configurado y disponible
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

    case provider do
      :openai -> embed_openai([text], cfg) |> unwrap_first()
      :anthropic -> {:error, "Anthropic no soporta embeddings. Usa provider=openai o local."}
      _ -> embed_local(text, cfg)
    end
  end

  def embed_batch(texts, opts \\ []) do
    cfg = Delfos.Config.Manager.embedding()
    provider = Keyword.get(opts, :provider, cfg[:provider])
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
        Logger.warning("Anthropic no soporta embeddings. Cambia embedding.provider.")
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
      _ -> {:error, "Anthropic: respuesta vacía"}
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
  defp unwrap_first({:ok, []}), do: {:error, "Embedding vacío"}
  defp unwrap_first(err), do: err
end
