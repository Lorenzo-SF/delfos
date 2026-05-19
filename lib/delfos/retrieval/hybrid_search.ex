defmodule Delfos.Retrieval.HybridSearch do
  @moduledoc """
  Búsqueda híbrida: combina similitud vectorial, BM25 y traversal de grafo.
  Score final = alpha*vector + beta*bm25 + gamma*graph
  """
  require Logger

  alias Delfos.LLM.Client
  alias Delfos.Retrieval.{VectorSearch, BM25Search, GraphSearch, Reranker}

  def search(project_id, query, opts \\ []) do
    k = opts[:k] || Application.get_env(:delfos, :retrieval)[:top_k] || 20
    final_k = opts[:final_k] || Application.get_env(:delfos, :retrieval)[:final_k] || 5
    kind = opts[:kind]
    # :chunk | :symbol | :summary
    level = opts[:level]

    with {:ok, query_vec} <- Client.embed(query) do
      tasks = [
        Task.async(fn -> VectorSearch.search(project_id, query_vec, k, kind, level) end),
        Task.async(fn -> BM25Search.search(project_id, query, k, kind) end),
        Task.async(fn -> GraphSearch.related(project_id, query, min(k, 10)) end)
      ]

      [vector_results, bm25_results, graph_results] =
        Task.await_many(tasks, 15_000)

      cfg = Application.get_env(:delfos, :retrieval)

      results =
        Reranker.merge(
          [
            vector: {vector_results, cfg[:vector_weight]},
            bm25: {bm25_results, cfg[:bm25_weight]},
            graph: {graph_results, cfg[:graph_weight]}
          ],
          k: final_k
        )

      {:ok, results}
    end
  end
end
