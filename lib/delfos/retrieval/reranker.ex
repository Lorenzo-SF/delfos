defmodule Delfos.Retrieval.Reranker do
  @moduledoc """
  Reciprocal Rank Fusion (RRF) para combinar resultados de múltiples motores.
  k=60 es el valor estándar de la literatura. Scale-invariante: funciona
  independientemente de la escala de scores de cada motor.
  """

  @rrf_k 60
  @doc """
  API wrapper que acepta keyword list con tuplas `{resultados, peso}`.

  ## Ejemplo

      Reranker.merge(
        vector: {vector_results, 0.5},
        bm25: {bm25_results, 0.3},
        graph: {graph_results, 0.2},
        k: 3
      )
  """
  def merge(pairs) when is_list(pairs) do
    {sources, opts} = Keyword.split(pairs, [:vector, :bm25, :graph])
    k = Keyword.get(opts, :k, 7)

    weights = Map.new(sources, fn {key, {_results, weight}} -> {key, weight} end)

    source_lists =
      Map.new(sources, fn {key, {results, _weight}} -> {key, results} end)

    rrf_merge(Map.merge(%{vector: [], bm25: [], graph: []}, source_lists),
      k: k,
      weights: weights
    )
  end

  def rrf_merge(%{vector: v, bm25: b, graph: g}, opts \\ []) do
    k = Keyword.get(opts, :k, 7)
    weights = Keyword.get(opts, :weights, %{vector: 0.55, bm25: 0.25, graph: 0.20})

    # Calcular scores RRF para cada lista
    scored =
      [
        {v, weights.vector},
        {b, weights.bm25},
        {g, weights.graph}
      ]
      |> Enum.flat_map(fn {results, weight} ->
        results
        |> Enum.with_index(1)
        |> Enum.map(fn {result, rank} ->
          {result_id(result), weight / (@rrf_k + rank), result}
        end)
      end)

    # Acumular scores por ID
    scored
    |> Enum.reduce(%{}, fn {id, score, result}, acc ->
      case Map.get(acc, id) do
        nil ->
          Map.put(acc, id, {score, result})

        {prev_score, prev_result} ->
          # Merge metadata del resultado con mayor score individual
          merged = if score > prev_score, do: result, else: prev_result
          Map.put(acc, id, {prev_score + score, merged})
      end
    end)
    |> Map.values()
    |> Enum.sort_by(fn {score, _} -> score end, :desc)
    |> Enum.take(k)
    |> Enum.map(fn {score, result} ->
      Map.put(result, :combined_score, Float.round(score, 4))
    end)
  end

  defp result_id(%{id: id}) when not is_nil(id), do: id
  defp result_id(%{qualified_name: n}) when not is_nil(n), do: n
  defp result_id(%{content: c}) when not is_nil(c), do: :erlang.phash2(c)
  defp result_id(r), do: :erlang.phash2(r)
end
