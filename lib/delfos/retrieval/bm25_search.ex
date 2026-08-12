defmodule Delfos.Retrieval.BM25Search do
  @moduledoc """
  BM25 search via PostgreSQL full-text search with `tsvector 'simple'`.

  The `'simple'` configuration (instead of e.g. `'english'`) keeps the
  search language-agnostic — important for multilingual codebases.

  P5: the `chunks` table has a precomputed `tsv` column (GENERATED
  ALWAYS AS ... STORED) with a GIN index. We use it for the chunk
  path where the data is large and the queries are frequent. Symbols
  are few and don't need it yet.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def search(project_id, query, k \\ 25, kind \\ nil) do
    tsquery = build_tsquery(query)

    sym_query =
      from(s in Schema.Symbol,
        where: s.project_id == ^project_id,
        # Symbols: no precomputed tsv column (most projects have few
        # symbols, the cost of recomputing is negligible). For larger
        # projects, a future migration could add it.
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
    # C2: el flag `/u` activa Unicode. Sin él, `\w` matchea solo
    # `[A-Za-z0-9_]` (ASCII) y strippea acentos/chinos/emojis.
    # Con `/u`, matchea letras/dígitos/marca de cualquier script
    # (incluye acentos, �, ü, etc.).
    query
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 1))
    |> Enum.map(&"#{&1}:*")
    |> Enum.join(" & ")
    |> then(fn q -> if q == "", do: "''", else: q end)
  end
end
