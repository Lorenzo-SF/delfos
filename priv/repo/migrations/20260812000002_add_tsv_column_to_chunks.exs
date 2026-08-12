defmodule Delfos.Repo.Migrations.AddTsvColumnToChunks do
  use Ecto.Migration

  @moduledoc """
  P5: precompute `to_tsvector` on the chunks table.

  The current `BM25Search.search/3` calls `to_tsvector('simple', ...)`
  TWICE per query (once for WHERE, once for ORDER BY ts_rank).
  Each call is O(text_length) per row scanned.

  With a GENERATED ALWAYS AS ... STORED column, Postgres
  computes the tsvector once at INSERT/UPDATE and stores it
  alongside the row. The query becomes a simple filter on the
  precomputed column, which is also GIN-indexable.

  Backfill: Postgres backfills the new column on ALTER TABLE
  (default behaviour for non-volatile generated columns). For
  very large tables, this can lock the table briefly — the
  IF NOT EXISTS / concurrent index helps.
  """

  def change do
    # Add the generated column. Uses 'simple' config (matches
    # BM25Search) and ORs together the searchable fields.
    execute """
    ALTER TABLE chunks
    ADD COLUMN IF NOT EXISTS tsv tsvector
    GENERATED ALWAYS AS (
      to_tsvector('simple',
        coalesce(content, '') || ' ' || coalesce(content, '')
      )
    ) STORED
    """

    # GIN index for fast @@ lookups. Without this, the @@ operator
    # falls back to seq scan even on a generated column.
    execute """
    CREATE INDEX IF NOT EXISTS chunks_tsv_gin_idx
    ON chunks
    USING GIN (tsv)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS chunks_tsv_gin_idx"
    execute "ALTER TABLE chunks DROP COLUMN IF EXISTS tsv"
  end
end
