defmodule Delfos.Retrieval.GraphSearch do
  @moduledoc """
  Búsqueda por traversal del grafo de dependencias.

  Dado un query de texto, encuentra los símbolos cuyo nombre coincide
  y retorna sus vecinos directos e indirectos con un score basado en
  la distancia (hops):
    - vecino directo (1 hop): score 0.9
    - vecino a 2 hops:        score 0.6
    - vecino a 3 hops:        score 0.3

  El score no era real antes (hardcodeado a 0.5) — ahora refleja proximidad.
  """

  import Ecto.Query
  alias Delfos.Repo

  def related(project_id, query, k) do
    matching_ids =
      Repo.all(
        from(s in Delfos.Schema.Symbol,
          where: s.project_id == ^project_id,
          where: ilike(s.name, ^"%#{query}%") or ilike(s.qualified_name, ^"%#{query}%"),
          limit: 5,
          select: s.id
        )
      )

    if Enum.empty?(matching_ids) do
      []
    else
      # BFS hasta 3 hops con score decreciente
      results =
        bfs_with_score(
          matching_ids,
          project_id,
          [{1, 0.9}, {2, 0.6}, {3, 0.3}],
          MapSet.new(matching_ids)
        )

      results
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.uniq_by(& &1.id)
      |> Enum.take(k)
    end
  rescue
    _ -> []
  end

  # ---------------------------------------------------------------------------
  # BFS por niveles
  # ---------------------------------------------------------------------------

  defp bfs_with_score(_ids, _project_id, [], _visited), do: []

  defp bfs_with_score(ids, project_id, [{_hop, score} | rest_levels], visited) do
    neighbors =
      Repo.all(
        from(r in Delfos.Schema.Relationship,
          join: s in Delfos.Schema.Symbol,
          on: s.id == r.to_id or s.id == r.from_id,
          where: r.project_id == ^project_id,
          where: r.from_id in ^ids or r.to_id in ^ids,
          where: s.id not in ^MapSet.to_list(visited),
          select: %{
            id: s.id,
            content: s.content,
            name: s.name,
            kind: s.kind
          },
          distinct: true
        )
      )
      |> Enum.map(&Map.put(&1, :score, score))

    new_ids = Enum.map(neighbors, & &1.id)
    new_visited = Enum.reduce(new_ids, visited, &MapSet.put(&2, &1))

    deeper = bfs_with_score(new_ids, project_id, rest_levels, new_visited)
    neighbors ++ deeper
  end
end
