defmodule Delfos.LLM.Client do
  @moduledoc "Cliente HTTP genérico compatible con la API de OpenAI."

  def chat(messages, opts \\ []) do
    cfg = Application.get_env(:delfos, :llm)
    url = Keyword.get(opts, :url, cfg[:url])
    model = Keyword.get(opts, :model, cfg[:model])
    max_tokens = Keyword.get(opts, :max_tokens, cfg[:max_tokens])
    reasoning = Keyword.get(opts, :reasoning, "medium")

    Req.post("#{url}/v1/chat/completions",
      auth: {:bearer, cfg[:api_key]},
      json: %{
        model: model,
        messages: messages,
        max_tokens: max_tokens,
        stream: false,
        chat_template_kwargs: %{reasoning_effort: reasoning}
      },
      receive_timeout: cfg[:timeout_ms]
    )
    |> handle_response()
  end

  def embed(text, opts \\ []) do
    cfg = Application.get_env(:delfos, :embedding)
    url = Keyword.get(opts, :url, cfg[:url])
    model = Keyword.get(opts, :model, cfg[:model])

    case Req.post("#{url}/v1/embeddings",
           auth: {:bearer, cfg[:api_key]},
           json: %{model: model, input: String.slice(text, 0, 4000)},
           receive_timeout: cfg[:timeout_ms]
         ) do
      {:ok, %{status: 200, body: body}} ->
        vec = get_in(body, ["data", Access.at(0), "embedding"])
        {:ok, vec}

      {:ok, %{status: s, body: b}} ->
        {:error, "HTTP #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def embed_batch(texts, _opts \\ []) do
    cfg = Application.get_env(:delfos, :embedding)
    batch_size = cfg[:batch_size] || 32

    texts
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(fn batch ->
      case Req.post("#{cfg[:url]}/v1/embeddings",
             auth: {:bearer, cfg[:api_key]},
             json: %{model: cfg[:model], input: batch},
             receive_timeout: cfg[:timeout_ms]
           ) do
        {:ok, %{status: 200, body: body}} ->
          body["data"] |> Enum.map(& &1["embedding"])

        _ ->
          Enum.map(batch, fn _ -> nil end)
      end
    end)
  end

  defp handle_response({:ok, %{status: 200, body: body}}) do
    content = get_in(body, ["choices", Access.at(0), "message", "content"])
    {:ok, content}
  end

  defp handle_response({:ok, %{status: s, body: b}}), do: {:error, "HTTP #{s}: #{inspect(b)}"}
  defp handle_response({:error, reason}), do: {:error, reason}
end
