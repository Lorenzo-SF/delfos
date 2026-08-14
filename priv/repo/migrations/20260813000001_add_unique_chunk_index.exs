defmodule Delfos.Repo.Migrations.AddUniqueChunkIndex do
  use Ecto.Migration

  def up do
    # persist_chunk/5 usa `on_conflict: {:replace, ...}` con
    # `conflict_target: [:file_id, :chunk_index]`, pero la migración
    # original (20260515000004) nunca creó el unique index — el
    # upsert fallaba con `42P10 invalid_column_reference`.
    create unique_index(:chunks, [:file_id, :chunk_index])
  end

  def down do
    drop unique_index(:chunks, [:file_id, :chunk_index])
  end
end