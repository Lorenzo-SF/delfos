defmodule Delfos.Retrieval.HybridSearch do
  @moduledoc """
  Búsqueda híbrida: vector semántico + BM25 + grafo con RRF.
  Pesos configurables vía `delfos config set retrieval vector_weight 0.6`.

  Los tres motores se lanzan en paralelo con `Arrea.run_sync/2`.
  """

  alias Delfos.LLM.Client
  alias Delfos.Retrieval.{VectorSearch, BM25Search, GraphSearch, Reranker}
  alias Delfos.Config.Manager

  @spec search(
          Ecto.UUID.t(),
          String.t(),
          keyword()
        ) :: {:ok, [map()]}
  def search(project_id, query, opts \\ []) do
    cfg = Manager.retrieval()
    k = Keyword.get(opts, :k, cfg[:top_k] || 25)
    final_k = Keyword.get(opts, :final_k, cfg[:final_k] || 7)
    kind = Keyword.get(opts, :kind)
    level = Keyword.get(opts, :level)

    weights = %{
      vector: cfg[:vector_weight] || 0.55,
      bm25: cfg[:bm25_weight] || 0.25,
      graph: cfg[:graph_weight] || 0.20
    }

    search_type = level || :chunk

    # Ejecutar los tres motores en paralelo via Arrea.run_sync (public facade).
    # C-2 audit fix: Arrea.Parallel es @moduledoc false; usamos la fachada.
    [vector_res, bm25_res, graph_res] =
      Arrea.run_sync(
        [
          fn -> VectorSearch.search_with_embed(project_id, query, k, kind, search_type) end,
          fn -> BM25Search.search(project_id, query, k, kind) end,
          fn -> GraphSearch.search(project_id, query, k) end
        ],
        workers: 3,
        timeout: 15_000
      )

    vector_list = extract_result(vector_res)
    bm25_list = extract_result(bm25_res)
    graph_list = extract_result(graph_res)

    all = %{vector: vector_list, bm25: bm25_list, graph: graph_list}
    {:ok, Reranker.rrf_merge(all, weights: weights, k: final_k)}
  end

  defp extract_result({:ok, %{result: {:ok, list}}}) when is_list(list), do: list
  defp extract_result({:ok, %{result: list}}) when is_list(list), do: list
  defp extract_result(_), do: []
end
