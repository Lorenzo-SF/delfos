defmodule Delfos.Repo.Migrations.AddFileLevelRelationships do
  use Ecto.Migration

  @moduledoc """
  Adds nullable `from_file_id` / `to_file_id` to relationships so we
  can persist file-level dependency edges (mix xref output, regex
  imports/aliases).

  The relationships table was originally symbol-level only (FKs to
  symbols.id). But `mix xref graph` and the regex-based import graph
  produce edges at the FILE level (file A imports file B). The
  previous behaviour was to silently drop these edges in
  GraphBuilder.persist_edges/3 (the lookup `f.path == ^rel` would
  return nil for non-absolute paths, and even when fixed, the
  insertion would crash with FK violation because from_id was being
  assigned a file UUID).

  Schema changes:
  - Add `from_file_id` (uuid, nullable, FK to files)
  - Add `to_file_id`   (uuid, nullable, FK to files)
  - Make `from_id` nullable (was NOT NULL)
  - Make `to_id`   nullable (was NOT NULL)
  - Add CHECK constraint: exactly one of (from_id, from_file_id) is
    set, and the same for the to_ pair. Enforced via app-level
    changeset validation (the CHECK would require a complex
    expression; Ecto's validate_required + custom validation is
    simpler).

  The `kind` field discriminates the edge type:
  - "imports"       → symbol-level, from_id + to_id
  - "imports_file"  → file-level,   from_file_id + to_file_id
  """

  def up do
    alter table(:relationships) do
      add :from_file_id, references(:files, type: :binary_id, on_delete: :delete_all), null: true
      add :to_file_id,   references(:files, type: :binary_id, on_delete: :delete_all), null: true

      # Make the symbol FKs nullable so file-level edges can have NULL here
      modify :from_id, :binary_id, null: true
      modify :to_id,   :binary_id, null: true
    end

    # Index for the new columns (the file_id ones are the workhorse for
    # file-level queries; from_id was already indexed).
    create index(:relationships, [:from_file_id])
    create index(:relationships, [:to_file_id])
    create index(:relationships, [:project_id, :kind])
  end

  def down do
    # Drop the file-level edges first (they reference NULL anyway)
    execute """
    DELETE FROM relationships WHERE from_file_id IS NOT NULL OR to_file_id IS NOT NULL
    """

    drop index(:relationships, [:to_file_id])
    drop index(:relationships, [:from_file_id])
    drop index(:relationships, [:project_id, :kind])

    alter table(:relationships) do
      remove :from_file_id
      remove :to_file_id

      modify :from_id, :binary_id, null: false
      modify :to_id,   :binary_id, null: false
    end
  end
end