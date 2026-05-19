defmodule Delfos.Retrieval.BM25Search do
  @moduledoc """
  Búsqueda full-text sobre símbolos y chunks usando PostgreSQL tsvector.

  Usa la configuración `'simple'` en lugar de `'spanish'` porque el código
  fuente contiene identificadores en inglés y nombres técnicos que no deben
  ser stemmeados por el diccionario en español.
  """

  import Ecto.Query
  alias Delfos.Repo

  def search(project_id, query, k, kind \\ nil) do
    base =
      from(s in Delfos.Schema.Symbol,
        where: s.project_id == ^project_id,
        where:
          fragment(
            "to_tsvector('simple', coalesce(?,'') || ' ' || coalesce(?,'')) @@ plainto_tsquery('simple', ?)",
            s.name,
            s.content,
            ^query
          ),
        order_by:
          fragment(
            "ts_rank(to_tsvector('simple', coalesce(?,'') || ' ' || coalesce(?,'')), plainto_tsquery('simple', ?)) DESC",
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
              "ts_rank(to_tsvector('simple', coalesce(?,'') || ' ' || coalesce(?,'')), plainto_tsquery('simple', ?))",
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
