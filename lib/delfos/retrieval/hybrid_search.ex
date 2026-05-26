defmodule Delfos.Retrieval.HybridSearch do
  @moduledoc """
  Búsqueda híbrida con fallback offline y timeout por retriever.
  Si el embedding falla, ignora vector y usa BM25 + grafo.
  """
  require Logger
  alias Delfos.LLM.Client
  alias Delfos.Retrieval.{VectorSearch, BM25Search, GraphSearch, Reranker}

  def search(project_id, query, opts \\ []) do
    k = opts[:k] || Application.get_env(:delfos, :retrieval)[:top_k] || 20
    final_k = opts[:final_k] || Application.get_env(:delfos, :retrieval)[:final_k] || 5
    kind = opts[:kind]
    level = opts[:level]

    query_vec =
      case Client.embed(query) do
        {:ok, vec} ->
          vec

        _ ->
          Logger.warning("Embedding falló. Activando modo degradado (BM25+Grafo)")
          nil
      end

    tasks = [
      Task.async(fn ->
        if query_vec, do: VectorSearch.search(project_id, query_vec, k, kind, level), else: []
      end),
      Task.async(fn -> BM25Search.search(project_id, query, k, kind) end),
      Task.async(fn -> GraphSearch.related(project_id, query, min(k, 10)) end)
    ]

    [vector_results, bm25_results, graph_results] =
      Task.yield_many(tasks, 12_000)
      |> Enum.map(fn {_task, res} -> res || :timeout end)
      |> Enum.map(fn
        {:ok, val} -> val
        :timeout -> []
      end)

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
