defmodule Delfos.Retrieval.GraphSearch do
  import Ecto.Query
  alias Delfos.Repo

  def related(project_id, query, k) do
    # Busca símbolos cuyo nombre coincide y trae sus vecinos en el grafo
    matching =
      Repo.all(
        from(s in Delfos.Schema.Symbol,
          where: s.project_id == ^project_id,
          where: ilike(s.name, ^"%#{query}%") or ilike(s.qualified_name, ^"%#{query}%"),
          limit: 5,
          select: s.id
        )
      )

    case(matching) do
      list when is_list(list) and length(list) == 0 ->
        []

      ids ->
        Repo.all(
          from(r in Delfos.Schema.Relationship,
            where: r.project_id == ^project_id,
            where: r.from_id in ^ids or r.to_id in ^ids,
            join: s in Delfos.Schema.Symbol,
            on: s.id == r.to_id or s.id == r.from_id,
            where: s.id not in ^ids,
            limit: ^k,
            select: %{id: s.id, content: s.content, name: s.name, kind: s.kind, score: 0.5}
          )
        )
    end
  rescue
    _ -> []
  end
end
