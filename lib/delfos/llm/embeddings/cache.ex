defmodule Delfos.Embeddings.Cache do
  @moduledoc """
  ETS-backed LRU cache for embeddings.

  FE-3: avoids re-embedding the same text. Key insight — the original
  plan was to plug into `Candil.Prompt.Cache`, but that module
  doesn't exist in candil 3.0. So we implement the cache locally in
  delfos.

  Architecture:
    * `:delfos_embeddings_cache` ETS table, `:public`,
      `read_concurrency: true`. Reads are O(1) and lock-free.
    * `:persistent_term` for hit/miss counters + total keys.
    * Soft LRU: when `max_size` reached, delete ~25% of entries
      using `:rand.uniform/1` to pick victims. This avoids keeping
      a separate ordered structure (priority queue) — the cache
      is approximate-LRU, not strict. Good enough for embeddings
      where "recently used" is what matters.
    * Disable with `Application.put_env(:delfos, :embeddings_cache,
      false)` (default: enabled).
  """

  require Logger

  @table :delfos_embeddings_cache
  @max_size_default 50_000
  @evict_fraction 0.25

  # Persistent keys for stats
  @stats_keys %{
    hits: {__MODULE__, :hits},
    misses: {__MODULE__, :misses},
    puts: {__MODULE__, :puts},
    evictions: {__MODULE__, :evictions}
  }

  @doc """
  Returns the cache stats: hits, misses, puts, evictions, current size.
  """
  def stats do
    size =
      case :ets.whereis(@table) do
        :undefined -> 0
        _ -> :ets.info(@table, :size) || 0
      end

    %{
      enabled: enabled?(),
      max_size: max_size(),
      size: size,
      hits: :persistent_term.get(@stats_keys.hits, 0),
      misses: :persistent_term.get(@stats_keys.misses, 0),
      puts: :persistent_term.get(@stats_keys.puts, 0),
      evictions: :persistent_term.get(@stats_keys.evictions, 0)
    }
  end

  @doc """
  Whether the cache is enabled (default: true, configurable via
  `:delfos, :embeddings_cache`).
  """
  def enabled? do
    Application.get_env(:delfos, :embeddings_cache, true)
  end

  @doc """
  Maximum cache size (soft cap). Configurable via
  `:delfos, :embeddings_cache_max_size`.
  """
  def max_size do
    Application.get_env(:delfos, :embeddings_cache_max_size, @max_size_default)
  end

  @doc """
  Look up a cached embedding by text. Returns `{:ok, vec}` or
  `:miss`. The text is hashed with SHA256 for the ETS key.
  """
  def lookup(text) when is_binary(text) do
    key = hash_key(text)

    if enabled?() do
      ensure_table()

      case :ets.lookup(@table, key) do
        [{^key, vec}] ->
          bump_counter(:hits)
          {:ok, vec}

        [] ->
          bump_counter(:misses)
          :miss
      end
    else
      :miss
    end
  end

  def lookup(_), do: :miss

  @doc """
  Store an embedding for a text. Triggers eviction if over the
  soft cap.
  """
  def put(text, vec) when is_binary(text) and is_list(vec) do
    if enabled?() do
      ensure_table()
      key = hash_key(text)
      :ets.insert(@table, {key, vec})
      bump_counter(:puts)
      maybe_evict()
      :ok
    else
      :ok
    end
  end

  def put(_text, _vec), do: :ok

  @doc """
  Wrap a batch embed call with the cache. For each text, check cache
  first; for misses, the caller should batch them and pass the
  results back via `fill_misses/3` to populate the cache.
  """
  def lookup_batch(texts) when is_list(texts) do
    Enum.map(texts, &lookup/1)
  end

  @doc """
  Populate cache for a list of (text, vec) pairs in a single
  ETS transaction. Faster than calling `put/2` per item.

  Silently drops nil vectors (embed failures) so callers can pass
  the raw output of CandilBridge.embed_batch/2 without filtering.
  """
  def fill_misses(pairs) when is_list(pairs) do
    if enabled?() do
      ensure_table()

      objects =
        pairs
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Enum.map(fn {text, vec} -> {hash_key(text), vec} end)

      :ets.insert(@table, objects)
      bump_counter(:puts, length(objects))
      maybe_evict()
      :ok
    else
      :ok
    end
  end

  @doc """
  Drop all cached embeddings (for tests, or after model swap).
  """
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc """
  Print a one-line summary of the cache to stdout. Useful for
  `delfos status --statistics`.
  """
  def print_summary do
    %{size: size, hits: h, misses: m, puts: p} = stats()
    total = h + m

    hit_rate =
      if total > 0,
        do: Float.round(h / total * 100, 1),
        else: 0.0

    IO.puts(
      "  │ Embeddings cache: #{size} entries, " <>
        "#{h} hits / #{m} misses (#{hit_rate}% hit rate), #{p} puts"
    )
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true
        ])

        :ok

      _ ->
        :ok
    end
  end

  defp hash_key(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  defp bump_counter(:hits), do: bump_counter(:hits, 1)
  defp bump_counter(:misses), do: bump_counter(:misses, 1)

  defp bump_counter(:puts), do: bump_counter(:puts, 1)

  defp bump_counter(kind, n) do
    key = Map.fetch!(@stats_keys, kind)
    current = :persistent_term.get(key, 0)
    :persistent_term.put(key, current + n)
  end

  # Soft LRU: when we exceed max_size, evict a random ~25% of entries.
  # This is approximate but avoids tracking access order. For
  # embeddings where the working set is "recently used", this is good
  # enough. Strict LRU would need a separate ordered index.
  defp maybe_evict do
    size = :ets.info(@table, :size) || 0
    max = max_size()

    if size > max do
      to_evict = trunc(size * @evict_fraction)
      victims = Enum.take_random(:ets.tab2list(@table), to_evict)
      :ets.delete(@table, Enum.map(victims, fn {k, _v} -> k end))
      bump_counter(:evictions, length(victims))
    end

    :ok
  end
end
