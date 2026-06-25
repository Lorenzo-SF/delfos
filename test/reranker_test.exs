defmodule Delfos.Retrieval.RerankerTest do
  use ExUnit.Case, async: true

  alias Delfos.Retrieval.Reranker

  @id1 "11111111-1111-1111-1111-111111111111"
  @id2 "22222222-2222-2222-2222-222222222222"
  @id3 "33333333-3333-3333-3333-333333333333"

  @tag :skip
  test "combina resultados de múltiples fuentes" do
    vector_results = [%{id: @id1, content: "fn auth", score: 0.9}]

    bm25_results = [
      %{id: @id1, content: "fn auth", score: 0.8},
      %{id: @id2, content: "fn payment", score: 0.6}
    ]

    graph_results = [%{id: @id3, content: "fn related", score: 0.5}]

    results =
      Reranker.merge(
        vector: {vector_results, 0.5},
        bm25: {bm25_results, 0.3},
        graph: {graph_results, 0.2},
        k: 3
      )

    assert length(results) == 3
    # id1 debe ser el primero (aparece en vector y bm25)
    assert List.first(results).id == @id1
  end

  @tag :skip
  test "deduplica resultados del mismo id" do
    results_a = [%{id: @id1, content: "fn", score: 0.9}]
    results_b = [%{id: @id1, content: "fn", score: 0.8}]

    results =
      Reranker.merge(
        vector: {results_a, 0.5},
        bm25: {results_b, 0.5},
        graph: {[], 0.0},
        k: 5
      )

    assert length(results) == 1
    assert List.first(results).combined_score > 0.8
  end
end
