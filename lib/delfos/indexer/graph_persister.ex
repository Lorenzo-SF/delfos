defmodule Delfos.Indexer.GraphPersister do
  @moduledoc """
  Persists graph edges (symbol references, imports, calls) to the database.

  Extracted from `Delfos.Indexer.GraphBuilder` (iter-044) to separate
  the build logic from the persistence logic — improves SRP and makes
  the persistence layer independently testable.

  ## Functions

    * `persist_edges/4` — batch inserts edges using a single
      `Repo.insert_all` call (PE-3 perf fix).
    * `delete_edges_for_paths/2` — removes edges for a list of paths
      before re-indexing.

  ## Why a single batch insert

  The previous implementation did N queries (one per edge) plus 2N
  file lookups.  With this batch approach we use 2 queries total
  (1 pre-load files + 1 insert_all).  Significant speedup on large
  codebases.
  """

  alias Delfos.Repo

  @doc """
  Batch-inserts edges of a given kind into the relationships table.

  `edges` is a list of `{from_path, to_path}` tuples.
  `kind` is a string ("imports_symbol", "imports_file", "calls", etc.).
  `files_by_path` is a map of path → `%Delfos.Schema.File{}` (pre-loaded).
  """
  @spec persist_edges([{String.t(), String.t()}], Schema.Project.t(), String.t(), map()) :: :ok
  def persist_edges(edges, project, kind, files_by_path) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    use_file_ids = kind == "imports_file"

    rows =
      Enum.flat_map(edges, fn {from_path, to_path} ->
        from_file = Map.get(files_by_path, from_path)
        to_file = Map.get(files_by_path, to_path)

        cond do
          is_nil(from_file) or is_nil(to_file) ->
            []

          from_file.id == to_file.id ->
            []

          true ->
            [
              %{
                project_id: project.id,
                from_id: if(use_file_ids, do: nil, else: from_file.id),
                to_id: if(use_file_ids, do: nil, else: to_file.id),
                from_file_id: if(use_file_ids, do: from_file.id, else: nil),
                to_file_id: if(use_file_ids, do: to_file.id, else: nil),
                kind: kind,
                inserted_at: now,
                updated_at: now
              }
            ]
        end
      end)

    if rows == [] do
      :ok
    else
      Repo.insert_all(Delfos.Schema.Relationship, rows, on_conflict: :nothing)
    end
  end

  @doc """
  Deletes relationships that reference any of the given paths.

  Used during incremental re-indexing to clean up stale edges before
  the new batch is inserted.
  """
  @spec delete_edges_for_paths(Schema.Project.t(), [String.t()]) :: :ok
  def delete_edges_for_paths(project, paths) when is_list(paths) do
    if paths == [] do
      :ok
    else
      query = Ecto.Query.from(r in Delfos.Schema.Relationship,
        where: r.project_id == ^project.id,
        join: f in Delfos.Schema.File,
        on: r.from_file_id == f.id or r.from_id == f.id,
        where: f.path in ^paths
      )

      Repo.delete_all(query)
      :ok
    end
  end
end
