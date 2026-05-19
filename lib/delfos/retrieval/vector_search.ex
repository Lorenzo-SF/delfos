defmodule Delfos.Retrieval.VectorSearch do
  import Ecto.Query
  alias Delfos.Repo

  def search(project_id, query_vec, k, kind \\ nil, level \\ nil) do
    table = table_for_level(level)

    query =
      from(r in table,
        where: r.project_id == ^project_id,
        order_by: fragment("embedding <=> ?::vector", ^query_vec),
        limit: ^k,
        select: %{
          id: r.id,
          content: r.content,
          kind: fragment("?::text", type(^"symbol", :string)),
          score: fragment("1 - (embedding <=> ?::vector)", ^query_vec)
        }
      )

    query = if kind, do: where(query, [r], r.kind == ^kind), else: query

    Repo.all(query)
  rescue
    _e -> []
  end

  defp table_for_level(:summary), do: Delfos.Schema.Summary
  defp table_for_level(:symbol), do: Delfos.Schema.Symbol
  defp table_for_level(_), do: Delfos.Schema.Chunk
end
