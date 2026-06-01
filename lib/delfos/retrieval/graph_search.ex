defmodule Delfos.Retrieval.GraphSearch do
  @moduledoc "Búsqueda por expansión de grafo: dado un símbolo, devuelve sus vecinos por hop."

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  @hop_scores %{1 => 0.9, 2 => 0.6, 3 => 0.3}

  def search(project_id, query, k \\ 25) do
    # Buscar símbolo semilla por nombre exacto o parcial
    seed =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^project_id,
          where: ilike(s.name, ^"%#{query}%") or ilike(s.qualified_name, ^"%#{query}%"),
          limit: 1
        )
      )

    if seed do
      bfs_expand(seed, project_id, k)
    else
      []
    end
  end

  defp bfs_expand(seed, project_id, k) do
    Enum.flat_map(1..3, fn hop ->
      ids = hop_neighbors(seed.id, project_id, hop)
      score = Map.get(@hop_scores, hop, 0.1)

      Repo.all(
        from(s in Schema.Symbol,
          where: s.id in ^ids,
          select: %{
            id: s.id,
            name: s.name,
            qualified_name: s.qualified_name,
            kind: s.kind,
            language: s.language,
            file_id: s.file_id,
            line_start: s.line_start,
            content: s.content,
            summary: s.summary,
            score: ^score
          }
        )
      )
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(k)
  end

  defp hop_neighbors(symbol_id, project_id, 1) do
    direct_callers(symbol_id, project_id) ++ direct_callees(symbol_id, project_id)
  end

  defp hop_neighbors(symbol_id, project_id, hop) do
    first_hop = hop_neighbors(symbol_id, project_id, 1)
    Enum.flat_map(first_hop, &hop_neighbors(&1, project_id, hop - 1))
  end

  defp direct_callers(symbol_id, project_id) do
    Repo.all(
      from(r in Schema.Relationship,
        where: r.to_id == ^symbol_id and r.project_id == ^project_id,
        select: r.from_id
      )
    )
  end

  defp direct_callees(symbol_id, project_id) do
    Repo.all(
      from(r in Schema.Relationship,
        where: r.from_id == ^symbol_id and r.project_id == ^project_id,
        select: r.to_id
      )
    )
  end
end
