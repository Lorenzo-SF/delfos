defmodule Delfos.Benchmarks.Retrieval do
  @moduledoc """
  FE-2: retrieval eval set + benchmarks.

  Measures quality of the hybrid search on a hand-curated set of
  queries against the cacafuti repo itself. Computes:
    - precision@k (what fraction of top-k results are relevant)
    - recall@k   (what fraction of all relevant results appear in top-k)
    - MRR         (mean reciprocal rank of first relevant result)

  These are NOT integration tests (no DB). They run against the
  in-memory helpers so they're fast and deterministic, but the
  actual retrieval quality still needs Postgres + embeddings to
  validate end-to-end. Run via:

      mix run benchmarks/retrieval/eval.exs
  """

  # Curated queries: {query, expected_first_relevant_symbol}
  # `expected_first_relevant_symbol` is matched against result
  # `:qualified_name` (case-insensitive substring).
  @queries [
    {"authentication middleware", ["Auth", "authenticate", "middleware"]},
    {"database schema migrations", ["migration", "migrations", "schema"]},
    {"rate limiting", ["rate_limit", "RateLimit", "throttle"]},
    {"HTTP client adapter", ["HTTP", "Adapter", "Http"]},
    {"circuit breaker", ["CircuitBreaker", "circuit", "breaker"]}
  ]

  @doc """
  Computes precision@k for a single query given retrieved results
  and a list of expected substrings.
  """
  def precision_at_k(results, k, expected_substrings) do
    top = Enum.take(results, k)

    hits =
      Enum.count(top, fn r ->
        name = String.downcase(to_string(r[:name] || r[:qualified_name] || ""))
        Enum.any?(expected_substrings, &String.contains?(name, String.downcase(&1)))
      end)

    hits / max(k, 1)
  end

  @doc """
  Mean reciprocal rank: 1/position of the first relevant result.
  Returns 0.0 if no relevant result in the list.
  """
  def mrr(results, expected_substrings) do
    indexed = Enum.with_index(results, 1)

    case Enum.find(indexed, fn {r, _pos} ->
           name = String.downcase(to_string(r[:name] || r[:qualified_name] || ""))
           Enum.any?(expected_substrings, &String.contains?(name, String.downcase(&1)))
         end) do
      {_r, pos} -> 1.0 / pos
      nil -> 0.0
    end
  end

  @doc """
  Run the curated eval set against a retrieval function.
  `retrieval_fn` receives a query string and returns a list of maps
  with at least `:name` or `:qualified_name`.
  """
  def run_eval(retrieval_fn, k \\ 5) do
    @queries
    |> Enum.map(fn {query, expected} ->
      results = retrieval_fn.(query)

      %{
        query: query,
        expected: expected,
        results_count: length(results),
        precision_at_k: precision_at_k(results, k, expected),
        mrr: mrr(results, expected),
        first_hit: first_relevant_name(results, expected)
      }
    end)
    |> summarize(k)
  end

  defp first_relevant_name(results, expected_substrings) do
    Enum.find_value(results, fn r ->
      name = to_string(r[:name] || r[:qualified_name] || "")

      if Enum.any?(
           expected_substrings,
           &String.contains?(String.downcase(name), String.downcase(&1))
         ),
         do: name
    end)
  end

  defp summarize(rows, k) do
    n = length(rows)
    avg_precision = Enum.sum(Enum.map(rows, & &1.precision_at_k)) / max(n, 1)
    avg_mrr = Enum.sum(Enum.map(rows, & &1.mrr)) / max(n, 1)

    %{
      queries_evaluated: n,
      k: k,
      avg_precision_at_k: Float.round(avg_precision, 3),
      avg_mrr: Float.round(avg_mrr, 3),
      details: rows
    }
  end

  @doc """
  Print a readable summary of the eval run.
  """
  def print_summary(%{
        queries_evaluated: n,
        k: k,
        avg_precision_at_k: p,
        avg_mrr: m,
        details: rows
      }) do
    IO.puts("\n=== Retrieval eval (k=#{k}) ===")
    IO.puts("Queries evaluated: #{n}")
    IO.puts("Avg precision@#{k}:  #{p}")
    IO.puts("Avg MRR:            #{m}")

    Enum.each(rows, fn row ->
      hit = row.first_hit || "(none)"

      IO.puts("  [#{row.precision_at_k}] \"#{row.query}\" → #{hit}")
    end)
  end
end
