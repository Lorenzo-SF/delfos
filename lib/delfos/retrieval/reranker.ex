defmodule Delfos.Retrieval.Reranker do
  @moduledoc """
  Combina resultados de múltiples retrievers usando Reciprocal Rank Fusion ponderado.
  contribution = weight / (rrf_k + rank)
  """
  @rrf_k 60

  def merge(sources, k: k) do
    rrf_scores =
      Enum.reduce(sources, %{}, fn {_name, {results, weight}}, acc ->
        results
        |> Enum.with_index(1)
        |> Enum.reduce(acc, fn {result, rank}, inner_acc ->
          contribution = weight / (@rrf_k + rank)

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
