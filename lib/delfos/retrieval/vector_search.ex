defmodule Delfos.Retrieval.VectorSearch do
  @moduledoc """
  Búsqueda por similitud vectorial usando pgvector (cosine distance).
  El campo `kind` en los resultados refleja el tipo real del registro
  (symbol.kind, "chunk", o "summary") en lugar de un literal hardcodeado.
  """

  import Ecto.Query
  alias Delfos.Repo

  def search(project_id, query_vec, k, kind \\ nil, level \\ nil) do
    case level do
      :summary -> search_summaries(project_id, query_vec, k)
      :symbol -> search_symbols(project_id, query_vec, k, kind)
      _ -> search_chunks(project_id, query_vec, k)
    end
  rescue
    _e -> []
  end

  # ---------------------------------------------------------------------------
  # Búsqueda sobre chunks (default)
  # ---------------------------------------------------------------------------

  defp search_chunks(project_id, query_vec, k) do
    Repo.all(
      from(c in Delfos.Schema.Chunk,
        where: c.project_id == ^project_id,
        where: not is_nil(c.embedding),
        order_by: fragment("embedding <=> ?::vector", ^query_vec),
        limit: ^k,
        select: %{
          id: c.id,
          content: c.content,
          kind: "chunk",
          name: fragment("''"),
          score: fragment("1 - (embedding <=> ?::vector)", ^query_vec)
        }
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Búsqueda sobre símbolos
  # ---------------------------------------------------------------------------

  defp search_symbols(project_id, query_vec, k, kind) do
    query =
      from(s in Delfos.Schema.Symbol,
        where: s.project_id == ^project_id,
        where: not is_nil(s.embedding),
        order_by: fragment("embedding <=> ?::vector", ^query_vec),
        limit: ^k,
        select: %{
          id: s.id,
          content: s.content,
          kind: s.kind,
          name: s.name,
          score: fragment("1 - (embedding <=> ?::vector)", ^query_vec)
        }
      )

    query = if kind, do: where(query, [s], s.kind == ^kind), else: query
    Repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # Búsqueda sobre summaries
  # ---------------------------------------------------------------------------

  defp search_summaries(project_id, query_vec, k) do
    Repo.all(
      from(s in Delfos.Schema.Summary,
        where: s.project_id == ^project_id,
        where: not is_nil(s.embedding),
        order_by: fragment("embedding <=> ?::vector", ^query_vec),
        limit: ^k,
        select: %{
          id: s.id,
          content: s.content,
          kind: "summary",
          name: s.scope,
          score: fragment("1 - (embedding <=> ?::vector)", ^query_vec)
        }
      )
    )
  end
end
