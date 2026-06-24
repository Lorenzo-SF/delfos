defmodule Delfos.Retrieval.BM25Search do
  @moduledoc """
  BM25 search via PostgreSQL full-text search with `tsvector 'simple'`.

  The `'simple'` configuration (instead of e.g. `'english'`) keeps the
  search language-agnostic — important for multilingual codebases.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def search(project_id, query, k \\ 25, kind \\ nil) do
    tsquery = build_tsquery(query)

    sym_query =
      from(s in Schema.Symbol,
        where: s.project_id == ^project_id,
        where:
          fragment(
            "to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(qualified_name,'') || ' ' || coalesce(content,'')) @@ to_tsquery('simple', ?)",
            ^tsquery
          ),
        order_by: [
          desc:
            fragment(
              "ts_rank(to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(content,'')), to_tsquery('simple', ?))",
              ^tsquery
            )
        ],
        limit: ^k,
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
          score:
            fragment(
              "ts_rank(to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(content,'')), to_tsquery('simple', ?))",
              ^tsquery
            )
        }
      )

    sym_query = if kind, do: where(sym_query, [s], s.kind == ^kind), else: sym_query

    Repo.all(sym_query)
  rescue
    # A-3 audit fix: log en lugar de tragar el error silenciosamente.
    # Si la DB está caída o la query falla por SQL, queremos saberlo.
    error ->
      require Logger
      Logger.warning("BM25Search.search falló: #{Exception.message(error)}")
      []
  end

  defp build_tsquery(query) do
    query
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 1))
    |> Enum.map(&"#{&1}:*")
    |> Enum.join(" & ")
    |> then(fn q -> if q == "", do: "''", else: q end)
  end
end
