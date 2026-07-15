defmodule Delfos.Retrieval.HybridSearch do
  @moduledoc """
  Búsqueda híbrida: vector semántico + BM25 + grafo con RRF.
  Pesos configurables vía `delfos config set retrieval vector_weight 0.6`.

  Los tres motores se lanzan en paralelo con `Arrea.run_sync/2`.
  """

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
    # `--llm-less` mode (B7): skip the vector engine entirely. BM25 +
    # graph are still merged via RRF but with vector weight zeroed.
    no_vector? = Keyword.get(opts, :no_vector, false)

    weights =
      if no_vector?,
        do: %{vector: 0.0, bm25: cfg[:bm25_weight] || 0.50, graph: cfg[:graph_weight] || 0.50},
        else: %{
          vector: cfg[:vector_weight] || 0.55,
          bm25: cfg[:bm25_weight] || 0.25,
          graph: cfg[:graph_weight] || 0.20
        }

    search_type = level || :chunk

    # Ejecutar los tres motores en paralelo via Arrea.run_sync (public facade).
    # C-2 audit fix: Arrea.Parallel es @moduledoc false; usamos la fachada.
    jobs =
      if no_vector? do
        [
          fn -> BM25Search.search(project_id, query, k, kind) end,
          fn -> GraphSearch.search(project_id, query, k) end
        ]
      else
        [
          fn -> VectorSearch.search_with_embed(project_id, query, k, kind, search_type) end,
          fn -> BM25Search.search(project_id, query, k, kind) end,
          fn -> GraphSearch.search(project_id, query, k) end
        ]
      end

    raw_results = Arrea.run_sync(jobs, workers: length(jobs), timeout: 15_000)

    {vector_list, bm25_list, graph_list} =
      if no_vector? do
        {[], extract_result(Enum.at(raw_results, 0)), extract_result(Enum.at(raw_results, 1))}
      else
        {
          extract_result(Enum.at(raw_results, 0)),
          extract_result(Enum.at(raw_results, 1)),
          extract_result(Enum.at(raw_results, 2))
        }
      end

    all = %{vector: vector_list, bm25: bm25_list, graph: graph_list}
    {:ok, Reranker.rrf_merge(all, weights: weights, k: final_k)}
  end

  # Normaliza los distintos shapes que pueden llegar aquí:
  # - `{:ok, %{result: list, exit_code: 0}}` — wrapper de Arrea.run_sync
  # - `{:ok, list}` — algunos motores devuelven esto directamente
  # - `list` — BM25 y Graph devuelven listas desnudas
  # - `%{result: list}` — variante sin wrapper de éxito
  # Antes solo aceptaba `%{result: list}`, descartando todos los demás
  # → query siempre devolvía [] aunque los motores devolvieran datos.
  defp extract_result({:ok, %{result: list}}) when is_list(list), do: list
  defp extract_result({:ok, list}) when is_list(list), do: list
  defp extract_result(list) when is_list(list), do: list
  defp extract_result(%{result: list}) when is_list(list), do: list
  defp extract_result(_), do: []
end
