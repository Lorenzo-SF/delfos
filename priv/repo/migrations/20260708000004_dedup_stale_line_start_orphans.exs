defmodule Delfos.Repo.Migrations.DedupStaleLineStartOrphans do
  use Ecto.Migration

  @moduledoc """
  Follow-up to 20260708000003.

  The first dedup migration required EXACT name match between orphan
  and sibling (`s2.name = s1.name`). That left 14 rows where the OLD
  regex parser stripped trailing characters from function names —
  e.g., `def valid?(...)` was recorded as `def valid(...)` because the
  regex `\\w+` excludes `?`.

  This migration catches those by also matching siblings whose qualified
  name contains the orphan's name after a `.` separator.

  Affects the `pote` test project. Safe to run on others (idempotent,
  no-ops when no orphans match).
  """

  def up do
    execute """
    DELETE FROM symbols s1
    USING projects p
    WHERE p.id = s1.project_id
      AND s1.qualified_name = s1.name
      AND s1.kind IN ('function', 'macro', 'type', 'callback', 'behaviour', 'use')
      AND EXISTS (
        SELECT 1 FROM symbols s2
        WHERE s2.file_id = s1.file_id
          AND s2.id != s1.id
          AND s2.line_start = s1.line_start
          AND s2.qualified_name LIKE '%.%'
          AND s2.qualified_name LIKE ('%.' || s1.name || '%')
      )
    """
  end

  def down, do: :ok
end
