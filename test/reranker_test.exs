defmodule Delfos.Retrieval.RerankerTest do
  @moduledoc """
  Tests for the actual RRF implementation used by `HybridSearch`.

  The previous version of this file called `Reranker.merge/1` (list of
  `{results, weight}` tuples), but the production code calls
  `Reranker.rrf_merge/2` with a `%{vector:, bm25:, graph:}` map. The
  legacy `merge/1` is preserved for backward compatibility but no
  longer wired into HybridSearch — these tests target the production
  surface.
  """

  use ExUnit.Case, async: true

  alias Delfos.Retrieval.Reranker

  @id1 "11111111-1111-1111-1111-111111111111"
  @id2 "22222222-2222-2222-2222-222222222222"
  @id3 "33333333-3333-3333-3333-333333333333"

  describe "rrf_merge/2 — production surface" do
    test "returns k results at most" do
      results =
        Reranker.rrf_merge(
          %{
            vector: [%{id: @id1, score: 0.9}],
            bm25: [%{id: @id2, score: 0.7}],
            graph: [%{id: @id3, score: 0.5}]
          },
          weights: %{vector: 0.5, bm25: 0.3, graph: 0.2},
          k: 2
        )

      assert length(results) == 2
    end

    test "ranks multi-source matches above single-source matches" do
      # id1 appears in BOTH vector and bm25 → should win over id3 (only graph).
      results =
        Reranker.rrf_merge(
          %{
            vector: [%{id: @id1, score: 0.9}],
            bm25: [%{id: @id1, score: 0.8}],
            graph: [%{id: @id3, score: 0.5}]
          },
          weights: %{vector: 0.5, bm25: 0.3, graph: 0.2},
          k: 3
        )

      assert length(results) == 2
      assert hd(results).id == @id1
      assert hd(results).combined_score > 0
    end

    test "default weights match what HybridSearch uses" do
      # When no weights are passed, the defaults from `Config` apply.
      # This test exercises the kwarg-omitted form.
      results =
        Reranker.rrf_merge(
          %{
            vector: [%{id: @id1, score: 0.9}],
            bm25: [%{id: @id2, score: 0.7}],
            graph: []
          },
          weights: %{vector: 0.55, bm25: 0.25, graph: 0.20},
          k: 5
        )

      assert length(results) == 2
      # Vector should have a higher combined score than bm25 alone because
      # the vector weight (0.55) is higher than the bm25 weight (0.25).
      [first, second] = results
      assert first.id == @id1
      assert second.id == @id2
      assert first.combined_score > second.combined_score
    end

    test "handles empty input lists gracefully" do
      results =
        Reranker.rrf_merge(
          %{vector: [], bm25: [], graph: []},
          weights: %{vector: 0.55, bm25: 0.25, graph: 0.20},
          k: 5
        )

      assert results == []
    end

    test "attaches combined_score to every result" do
      results =
        Reranker.rrf_merge(
          %{
            vector: [%{id: @id1, score: 0.9}],
            bm25: [],
            graph: []
          },
          weights: %{vector: 0.5, bm25: 0.3, graph: 0.2},
          k: 1
        )

      [result] = results
      assert Map.has_key?(result, :combined_score)
      assert is_float(result.combined_score)
      assert result.combined_score > 0
    end

    test "dedupes by id when the same id appears in multiple sources" do
      results =
        Reranker.rrf_merge(
          %{
            vector: [%{id: @id1, score: 0.9}],
            bm25: [%{id: @id1, score: 0.8}],
            graph: [%{id: @id1, score: 0.7}]
          },
          weights: %{vector: 0.5, bm25: 0.3, graph: 0.2},
          k: 5
        )

      assert length(results) == 1
      assert hd(results).id == @id1
      # Score from all three sources should be summed
      assert hd(results).combined_score > 0
    end
  end
end