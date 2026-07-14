defmodule Delfos.LLM.CandilBridge do
  require Logger

  @moduledoc """
  Bridge between `Delfos.LLM.Client` and `Candil`.

  `Candil` is the project's general-purpose LLM client (local models via
  llama.cpp or remote via OpenAI-compatible APIs). This bridge adapts
  the `Candil.chat/3,4`, `Candil.embed/3,4` and friends to the
  configuration shape and routing rules that `Delfos.LLM.Client`
  already exposes (per-use-case max_tokens, thinker model fallback,
  multi-provider support).

  When `Candil` is not available as a dependency (it's an optional
  `dev`/`test` dep), `available?/0` returns false and `Delfos.LLM.Client`
  falls back to the in-house `Req`-based implementation.

  ## Why a bridge module

  The intent is to **gradually** migrate `Delfos.LLM.Client` to `Candil`
  without breaking the existing public API. The bridge isolates the
  Candil-specific calls so swapping the implementation later is a
  single-module change.
  """

  @doc """
  Returns true when `Candil` is loaded and can be used. False otherwise.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Candil)
  end

  @doc """
  Performs a chat completion through `Candil.chat/3`.

  Builds a `Candil.Model` and `Candil.Provider` on the fly from
  `Delfos.Config.Manager.llm/0` so the existing config schema keeps
  working unchanged. The provider is set to `:openai` (the only
  OpenAI-compatible type Candil exposes); for `:anthropic`, the
  caller should fall back to `Delfos.LLM.Client`'s direct path.
  """
  @spec chat(list(), keyword(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(messages, llm_cfg, opts) do
    {model_name, max_tokens} = resolve(llm_cfg, opts)

    provider = %Candil.Provider{
      alias: :delfos_openai,
      type: :openai,
      base_url: llm_cfg[:url] || "https://api.openai.com",
      api_key: llm_cfg[:api_key]
    }

    model = %Candil.Model{
      alias: :delfos_model,
      type: :remote,
      name: model_name,
      provider: :delfos_openai,
      usage: [:chat]
    }

    Candil.chat(model, provider, messages, max_tokens: max_tokens)
  end

  @doc """
  Performs an embedding through `Candil.embed/3`. Returns
  `{:ok, [float()]}` or `{:error, term()}`.
  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, embed_cfg) do
    provider = %Candil.Provider{
      alias: :delfos_embed_openai,
      type: :openai,
      base_url: embed_cfg[:url] || "https://api.openai.com",
      api_key: embed_cfg[:api_key]
    }

    model = %Candil.Model{
      alias: :delfos_embed_model,
      type: :remote,
      name: embed_cfg[:model] || "text-embedding-3-small",
      provider: :delfos_embed_openai,
      usage: [:embed]
    }

    Candil.embed(model, provider, [text], [])
  end

  @doc """
  Performs a batch embedding. Returns a list (one entry per input text;
  `nil` for entries that failed).

  Validates the embedding dimension against `embed_cfg[:dim]` and falls
  back to `nil` for any vector whose length doesn't match. This is the
  safety net that prevents pgvector dimension errors at insert time
  when the embedding server is misconfigured (e.g. serving an OpenAI
  model under a jina URL).
  """
  @spec embed_batch([String.t()], keyword()) :: [list() | nil]
  def embed_batch(texts, embed_cfg) do
    batch_size = embed_cfg[:batch_size] || 48
    expected_dim = embed_cfg[:dim]

    texts
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(fn batch ->
      case do_embed_batch(batch, embed_cfg) do
        {:ok, vecs} when is_list(expected_dim) or is_integer(expected_dim) ->
          validate_dimensions(vecs, expected_dim)

        {:ok, vecs} ->
          vecs

        _ ->
          Enum.map(batch, fn _ -> nil end)
      end
    end)
  end

  defp validate_dimensions(vecs, expected_dim) do
    Enum.map(vecs, fn
      vec when is_list(vec) and length(vec) == expected_dim ->
        vec

      _other ->
        Logger.warning(
          "[CandilBridge] embedding dimension mismatch: expected #{expected_dim}, " <>
            "got a different size. Check that the server at the configured URL is serving the " <>
            "expected model (and that 'embedding.dim' in config matches)."
        )

        nil
    end)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp resolve(llm_cfg, opts) do
    use_case = Keyword.get(opts, :use_case, :query)

    use_thinker =
      use_case in [:explain, :query] and
        llm_cfg[:use_thinker_for_query] == true and
        llm_cfg[:thinker_url] not in [nil, ""]

    {model, max_tokens} =
      if use_thinker do
        {llm_cfg[:thinker_model],
         Keyword.get(opts, :max_tokens) || llm_cfg[:explain_max_tokens] || 600}
      else
        {llm_cfg[:model],
         Keyword.get(opts, :max_tokens) ||
           case use_case do
             :summarize -> llm_cfg[:max_tokens] || llm_cfg[:summarize_max_tokens] || 180
             :explain -> llm_cfg[:explain_max_tokens] || 600
             _ -> llm_cfg[:query_max_tokens] || 512
           end}
      end

    {model || "gpt-4o-mini", max_tokens}
  end

  defp do_embed_batch(texts, embed_cfg) do
    provider = %Candil.Provider{
      alias: :delfos_embed_openai,
      type: :openai,
      base_url: embed_cfg[:url] || "https://api.openai.com",
      api_key: embed_cfg[:api_key]
    }

    model = %Candil.Model{
      alias: :delfos_embed_model,
      type: :remote,
      name: embed_cfg[:model] || "text-embedding-3-small",
      provider: :delfos_embed_openai,
      usage: [:embed]
    }

    Candil.embed(model, provider, texts, [])
  end
end
