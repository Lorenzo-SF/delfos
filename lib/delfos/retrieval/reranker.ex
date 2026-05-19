defmodule Delfos.Retrieval.Reranker do
  @moduledoc "Combina resultados de múltiples retrievers con pesos y deduplica."

  def merge(sources, k: k) do
    all_results =
      Enum.flat_map(sources, fn {_name, {results, weight}} ->
        Enum.map(results, fn r -> Map.put(r, :weighted_score, (r[:score] || 0) * weight) end)
      end)

    # Agrupar por id y sumar scores ponderados
    all_results
    |> Enum.group_by(& &1.id)
    |> Enum.map(fn {id, entries} ->
      combined_score = Enum.sum(Enum.map(entries, & &1.weighted_score))
      base = List.first(entries)
      Map.merge(base, %{id: id, combined_score: combined_score})
    end)
    |> Enum.sort_by(& &1.combined_score, :desc)
    |> Enum.take(k)
  end
end
