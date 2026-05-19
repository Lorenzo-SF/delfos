defmodule Delfos.Retrieval.Reranker do
  @moduledoc """
  Combina resultados de múltiples retrievers usando Reciprocal Rank Fusion (RRF).

  RRF es más robusto que la suma ponderada lineal porque:
  1. No requiere normalizar scores entre retrievers (BM25 es 0..∞, vector es 0..1).
  2. Penaliza posiciones bajas en cada lista de forma consistente.
  3. El parámetro k=60 es el valor canónico de la literatura (Cormack et al. 2009).

  Score RRF de un documento d = Σ_r  1 / (k + rank_r(d))
  donde rank_r(d) es la posición de d en el retriever r (1-indexed).
  """

  @rrf_k 60

  @doc """
  Combina múltiples listas de resultados y devuelve los `k` mejores.

  `sources` es una lista de `{name, {results, _weight}}` — el peso se ignora
  porque RRF usa rangos, no scores absolutos.
  """
  def merge(sources, k: k) do
    # Construir mapa: id -> rrf_score acumulado
    rrf_scores =
      Enum.reduce(sources, %{}, fn {_name, {results, _weight}}, acc ->
        results
        |> Enum.with_index(1)
        |> Enum.reduce(acc, fn {result, rank}, inner_acc ->
          contribution = 1.0 / (@rrf_k + rank)

          Map.update(inner_acc, result.id, {contribution, result}, fn {score, r} ->
            {score + contribution, r}
          end)
        end)
      end)

    rrf_scores
    |> Enum.map(fn {id, {score, result}} ->
      Map.merge(result, %{id: id, combined_score: score})
    end)
    |> Enum.sort_by(& &1.combined_score, :desc)
    |> Enum.take(k)
  end
end
