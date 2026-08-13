defmodule Delfos.CLI.ProjectResolver do
  @moduledoc """
  Resolves the active project for a CLI command.

  FE-4: the schema supports multi-project (every relevant table has
  a `project_id` column, foreign keys wired up via `belongs_to :project`).
  But the CLI was using `Repo.one(from(p in Project, order_by: [desc:
  p.last_scanned], limit: 1))` to get THE active project — which only
  works if you have a single project.

  This module centralizes that lookup so individual commands can
  accept an explicit `--project <uuid>` flag and fall back to the
  most-recently-scanned project when no flag is given.

  # `Repo`/`Schema` aliases intentionally OMITTED: they create a
  # forward reference to modules that may not be compiled at the
  # time this file is processed (project_resolver.ex is the FIRST
  # CLI module compiled alphabetically). Use fully-qualified names
  # (`Delfos.Repo`, `Delfos.Schema.Project`) to avoid that warning.
  require Ecto.Query

  import Ecto.Query, only: [from: 2]

  @doc \"""
  Resolves a project from opts. Supports:
    * `:project` — a UUID string OR a `%Schema.Project{}` struct.
    * `:project_id` — same as `:project` (alias).
    * `:project_path` — a path string (matches the `path` column).

  Returns the project struct, or `nil` if nothing matches.

  When no flag is present, falls back to the most-recently-scanned
  project (preserves the original single-project behaviour).
  """
  @spec resolve(keyword()) :: module()
  def resolve(opts) do
    cond do
      proj = Keyword.get(opts, :project) || Keyword.get(opts, :project_id) ->
        resolve_by_id(proj)

      path = Keyword.get(opts, :project_path) ->
        resolve_by_path(path)

      true ->
        resolve_most_recent()
    end
  end

  @doc """
  Same as `resolve/1` but raises `ArgumentError` if no project
  found. For commands that REQUIRE a project.
  """
  @spec resolve!(keyword()) :: module()
  def resolve!(opts) do
    case resolve(opts) do
      nil -> raise ArgumentError, "No project found. Run 'delfos init <path>' first."
      proj -> proj
    end
  end

  defp resolve_by_id(nil), do: resolve_most_recent()

  # Use runtime struct check (is_struct) instead of pattern match
  # against %Schema.Project{} to avoid forcing `Schema.Project` to be
  # compiled before this module. Project struct is detected by name.
  defp resolve_by_id(proj) when is_struct(proj) do
    if proj.__struct__ == Delfos.Schema.Project do
      proj
    else
      resolve_most_recent()
    end
  end

  defp resolve_by_id(id) when is_binary(id) do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, where: p.id == ^id))
  end

  defp resolve_by_id(_), do: resolve_most_recent()

  defp resolve_by_path(path) when is_binary(path) do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, where: p.path == ^path))
  end

  defp resolve_by_path(_), do: resolve_most_recent()

  @doc """
  Returns the most-recently-scanned project, or nil. Used by
  background jobs (watcher) that don't have access to a flag.
  Prefer `resolve/1` for CLI commands.
  """
  @spec resolve_most_recent() :: module()
  def resolve_most_recent do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  end
end
