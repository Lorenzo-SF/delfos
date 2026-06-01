defmodule Delfos.Retrieval.VectorSearch do
  @moduledoc "Búsqueda por similitud coseno usando pgvector."

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.LLM.Client

  @doc "Busca embebiendo la query internamente (para uso en Arrea.Parallel)."
  def search_with_embed(project_id, query, k, kind, search_type) do
    case Client.embed(query) do
      {:ok, embedding} -> {:ok, search(project_id, embedding, k, kind, search_type)}
      err -> err
    end
  end

  @doc "Busca con un embedding ya generado."
  def search(project_id, embedding, k, kind, search_type \\ :chunk) do
    case search_type do
      :symbol -> search_symbols(project_id, embedding, k, kind)
      :summary -> search_summaries(project_id, embedding, k)
      _ -> search_chunks(project_id, embedding, k)
    end
  end

  defp search_chunks(project_id, embedding, k) do
    vec = pgvector_cast(embedding)

    Repo.all(
      from(c in Schema.Chunk,
        where: c.project_id == ^project_id and not is_nil(c.embedding),
        order_by: fragment("embedding <=> ?", ^vec),
        limit: ^k,
        select: %{
          id: c.id,
          kind: "chunk",
          content: c.content,
          file_id: c.file_id,
          line_start: c.line_start,
          score: fragment("1 - (embedding <=> ?)", ^vec)
        }
      )
    )
  end

  defp search_symbols(project_id, embedding, k, kind) do
    vec = pgvector_cast(embedding)

    query =
      from(s in Schema.Symbol,
        where: s.project_id == ^project_id and not is_nil(s.embedding),
        order_by: fragment("embedding <=> ?", ^vec),
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
          score: fragment("1 - (embedding <=> ?)", ^vec)
        }
      )

    query = if kind, do: where(query, [s], s.kind == ^kind), else: query
    Repo.all(query)
  end

  defp search_summaries(project_id, embedding, k) do
    vec = pgvector_cast(embedding)

    Repo.all(
      from(s in Schema.Summary,
        where: s.project_id == ^project_id and not is_nil(s.embedding),
        order_by: fragment("embedding <=> ?", ^vec),
        limit: ^k,
        select: %{
          id: s.id,
          kind: "summary",
          content: s.content,
          scope: s.scope,
          score: fragment("1 - (embedding <=> ?)", ^vec)
        }
      )
    )
  end

  defp pgvector_cast(embedding) when is_list(embedding) do
    Pgvector.new(embedding)
  end

  defp pgvector_cast(embedding), do: embedding
end
