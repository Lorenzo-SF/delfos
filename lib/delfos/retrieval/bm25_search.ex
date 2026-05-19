defmodule Delfos.Retrieval.BM25Search do
  import Ecto.Query
  alias Delfos.Repo

  def search(project_id, query, k, kind \\ nil) do
    base =
      from(s in Delfos.Schema.Symbol,
        where: s.project_id == ^project_id,
        where:
          fragment(
            "to_tsvector('spanish', coalesce(?,'') || ' ' || coalesce(?,'')) @@ plainto_tsquery('spanish', ?)",
            s.name,
            s.content,
            ^query
          ),
        order_by:
          fragment(
            "ts_rank(to_tsvector('spanish', coalesce(?,'') || ' ' || coalesce(?,'')), plainto_tsquery('spanish', ?)) DESC",
            s.name,
            s.content,
            ^query
          ),
        limit: ^k,
        select: %{
          id: s.id,
          content: s.content,
          name: s.name,
          kind: s.kind,
          score:
            fragment(
              "ts_rank(to_tsvector('spanish', coalesce(?,'') || ' ' || coalesce(?,'')), plainto_tsquery('spanish', ?))",
              s.name,
              s.content,
              ^query
            )
        }
      )

    base = if kind, do: where(base, [s], s.kind == ^kind), else: base
    Repo.all(base)
  rescue
    _ -> []
  end
end
