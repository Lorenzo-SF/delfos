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
  Returns true when rate limiting is configured for this bridge.
  Rate limiting uses `Apero.RateLimit` if available.

  iter-051: prevents bursting the provider when many MCP clients
  fire chat/embed concurrently.
  """
  @spec rate_limit_enabled?() :: boolean()
  def rate_limit_enabled? do
    Code.ensure_loaded?(Apero.RateLimit)
  end

  @doc """
  Checks the rate limit before a `chat/3` call. Returns :ok if allowed,
  `{:error, :rate_limited}` if not. No-op if Apero is unavailable.

  Rate limit: 30 requests per minute by default, configurable via
  `:delfos, :candil_bridge_rpm` config or `DELFOS_CANDIL_RPM` env var.
  """
  @spec check_rate_limit() :: :ok | {:error, :rate_limited}
  def check_rate_limit do
    if rate_limit_enabled? do
      rpm = rpm_from_env()

      case Apero.RateLimit.check(:candil_bridge, max: rpm, period: 60_000) do
        :ok -> :ok
        {:error, :rate_limited} -> {:error, :rate_limited}
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp rpm_from_env do
    case System.get_env("DELFOS_CANDIL_RPM") do
      nil -> default_rpm()
      "" -> default_rpm()
      val ->
        case Integer.parse(val) do
          {n, _} when n > 0 -> n
          _ -> default_rpm()
        end
    end
  end

  defp default_rpm do
    Application.get_env(:delfos, :candil_bridge_rpm, 30)
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
    base_url = llm_cfg[:url] || "https://api.openai.com"

    # SE-4 (S16): rechazar URLs inseguras ANTES de construir el
    # Candil.Provider. Esto bloquea configs maliciosas o
    # malformadas que apunten a http://attacker.com.
    Delfos.Config.URLValidator.validate!(base_url)

    provider = %Candil.Provider{
      alias: :delfos_openai,
      type: :openai,
      base_url: base_url,
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
    base_url = embed_cfg[:url] || "https://api.openai.com"

    # SE-4 (S16)
    Delfos.Config.URLValidator.validate!(base_url)

    provider = %Candil.Provider{
      alias: :delfos_embed_openai,
      type: :openai,
      base_url: base_url,
      api_key: embed_cfg[:api_key]
    }

    # Model name comes from the COMPILE-TIME `:delfos, :embedding` config
    # (see `config/config.exs`). The runtime JSON's `embedding.model`
    # field is ignored — it's an artefact from before this refactor and
    # would conflict with the LLama server's actual GGUF if used here.
    model = %Candil.Model{
      alias: :delfos_embed_model,
      type: :remote,
      name: compile_time_model_name(embed_cfg),
      provider: :delfos_embed_openai,
      usage: [:embed]
    }

    Candil.embed(model, provider, [text], [])
  end

  # Read the model name from compile-time config, falling back to the
  # JSON/embed_cfg value (legacy behaviour) and finally to a sensible
  # default if neither is set.
  @compile_time_embed_model Application.compile_env!(:delfos, :embedding)[:model]

  defp compile_time_model_name(embed_cfg) do
    @compile_time_embed_model ||
      embed_cfg[:model] ||
      "text-embedding-3-small"
  end

  @doc """
  Performs a batch embedding. Returns a list (one entry per input text;
  `nil` for entries that failed).

  Validates the embedding dimension against `embed_cfg[:dim]` and falls
  back to `nil` for any vector whose length doesn't match. This is the
  safety net that prevents pgvector dimension errors at insert time
  when the embedding server is misconfigured (e.g. serving an OpenAI
  model under a jina URL).

  C8: vectors are L2-normalized before returning. Cosine similarity
  via pgvector's `<=>` operator expects unit-norm vectors for
  ranking to be correct. The normalization happens app-side so we
  don't depend on a Postgres GENERATED column (which would need
  a migration and re-index of existing rows).
  """
  @spec embed_batch([String.t()], keyword()) :: [list() | nil]
  def embed_batch(texts, embed_cfg) do
    batch_size = embed_cfg[:batch_size] || 48
    # The expected dim is a single source of truth: the compile-time
    # value declared in `config/config.exs`. We intentionally ignore
    # any `embed_cfg[:dim]` the caller might pass — runtime config
    # cannot override it (see `Delfos.CLI.Commands.Config.@compile_time_fixed_keys`).
    # Falls back to `embed_cfg[:dim]` for tests that don't load the
    # application config.
    expected_dim =
      case Application.fetch_env(:delfos, :embedding) do
        {:ok, embed_env} -> embed_env[:dim] || embed_cfg[:dim] || 1536
        :error -> embed_cfg[:dim] || 1536
      end

    texts
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(fn batch ->
      case do_embed_batch(batch, embed_cfg) do
        {:ok, vecs} when is_list(expected_dim) or is_integer(expected_dim) ->
          vecs
          |> validate_dimensions(expected_dim)
          |> Enum.map(&normalize_or_nil/1)

        {:ok, vecs} ->
          Enum.map(vecs, &normalize_or_nil/1)

        _ ->
          Enum.map(batch, fn _ -> nil end)
      end
    end)
  end

  @doc """
  Normalizes a vector to unit L2 norm. Returns nil if the vector is
  zero (which would cause division-by-zero in cosine similarity).

  Useful for one-off normalization of existing rows in DB.
  """
  @spec normalize(list()) :: list() | nil
  def normalize(vec) when is_list(vec) and vec != [] do
    norm = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))

    if norm > 0.0 do
      Enum.map(vec, &(&1 / norm))
    else
      nil
    end
  end

  def normalize(_), do: nil

  defp normalize_or_nil(nil), do: nil

  defp normalize_or_nil(vec) when is_list(vec), do: normalize(vec)
  defp normalize_or_nil(_), do: nil

  defp validate_dimensions(vecs, expected_dim) do
    {ok_vecs, bad} =
      Enum.reduce(vecs, {[], 0}, fn
        vec, {ok, n} when is_list(vec) and length(vec) == expected_dim ->
          {[vec | ok], n}

        _other, {ok, n} ->
          {ok, n + 1}
      end)

    if bad > 0 do
      log_dimension_mismatch(expected_dim, bad)
    end

    ok_vecs |> Enum.reverse() |> pad_to_length(length(vecs))
  end

  # The dimension mismatch is the SAME problem every time (the server
  # is misconfigured), so logging it per-vector floods the scan with
  # 60+ identical lines. Dedupe via :persistent_term — log once per
  # mismatch size, not once per vector.
  defp log_dimension_mismatch(expected_dim, count) do
    key = {__MODULE__, :dim_mismatch, expected_dim}

    if :persistent_term.get(key, :unset) == :unset do
      :persistent_term.put(key, {expected_dim, count})

      Logger.warning(
        "[CandilBridge] #{count} embeddings had wrong dimension " <>
          "(expected #{expected_dim}). Check that the server at the " <>
          "configured URL is serving the expected model (and that " <>
          "'embedding.dim' in config matches). This warning is logged " <>
          "once per dimension mismatch; subsequent failures are counted " <>
          "but not re-logged for the rest of the process lifetime."
      )
    else
      {_, total} = :persistent_term.get(key)
      :persistent_term.put(key, {expected_dim, total + count})
    end
  end

  defp pad_to_length(vecs, total) when length(vecs) >= total, do: vecs
  defp pad_to_length(vecs, total), do: vecs ++ List.duplicate(nil, total - length(vecs))

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
      name: compile_time_model_name(embed_cfg),
      provider: :delfos_embed_openai,
      usage: [:embed]
    }

    Candil.embed(model, provider, texts, [])
  end
end
