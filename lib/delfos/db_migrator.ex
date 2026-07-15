defmodule Delfos.DBMigrator do
  @moduledoc """
  Ensures the pgvector column type for `embedding` matches the
  compile-time `:delfos, :embedding, :dim` value.

  ## Why this exists

  pgvector is strict — a `vector(N)` column rejects vectors of any
  other length with a hard error per `Repo.insert`. So the column
  type, the embed server's output dim, and delfos's
  `embedding.dim` config must all agree.

  Before this module, that agreement was enforced only by hand
  (a previous session ALTERed the DB to `vector(4096)` but left
  the on-disk migrations at `vector(1024)`, leaving new clones
  in an inconsistent state). The runtime check below guarantees
  that whatever `:delfos, :embedding, :dim` is compiled into the
  binary is what the live schema uses.

  ## Behaviour

  * On boot (called by `Delfos.CLI.main/1` via
    `Delfos.RepoStarter.start_repo/0`), runs `check_embedding_dim!/0`.
  * Reads the live dim by querying `pg_attribute.atttypmod` for the
    `embedding` column on each of `symbols`, `chunks`, `summaries`.
  * If any of those differ from the configured dim, emits a clear
    warning and applies `ALTER TABLE ... ALTER COLUMN embedding TYPE
    vector(<configured>) USING NULL` to each mismatched table, plus
    drops & recreates the `ivfflat` indexes (they are dim-specific).
  * All existing embeddings are NULLified (you can't reliably cast a
    1024-dim vector to a 4096-dim one). A re-scan is required after
    this happens; the warning tells the user to run `delfos scan --full`.

  ## Manual override

  You shouldn't ever need to run this by hand — `Delfos.CLI.main/1`
  invokes it via `RepoStarter.start_repo/0`. If you really want to:

      iex> Delfos.DBMigrator.check_embedding_dim!()
      :ok
  """

  require Logger

  alias Delfos.{Repo, Schema}

  @config_dim Application.compile_env!(:delfos, :embedding)[:dim] ||
                raise(
                  "config :delfos, :embedding, :dim is not set; " <>
                    "edit config/config.exs and recompile"
                )

  # Tables that hold an embedding column.
  @tables [
    {"symbols", "symbols_embedding_idx"},
    {"chunks", "chunks_embedding_idx"},
    {"summaries", "summaries_embedding_idx"}
  ]

  @doc """
  Returns the compile-time embedding dim declared in `:delfos, :embedding`.
  """
  @spec configured_dim() :: pos_integer()
  def configured_dim, do: @config_dim

  @doc """
  Returns the live dim of the symbols.embedding column, or
  `nil` if the table doesn't exist yet.
  """
  @spec live_symbols_dim() :: pos_integer() | nil
  def live_symbols_dim do
    pgvector_dim(Schema.Symbol.__schema__(:source))
  end

  @doc """
  Compare the live pgvector column dim of every embedding table
  against the compile-time configured dim. If any mismatch,
  emit a warning AND apply the ALTER TABLE inline.

  Idempotent: a no-op when everything matches.

  Returns `:ok | {:migrated, list_of_tables}`. When `:ok` is
  returned the DB is already at the configured dim.
  """
  @spec check_embedding_dim!() :: :ok | {:migrated, [String.t()]}
  def check_embedding_dim! do
    configured = @config_dim

    mismatches =
      Enum.flat_map(@tables, fn {table, _} ->
        case pgvector_dim(table) do
          ^configured -> []
          nil -> []
          other -> [{table, other}]
        end
      end)

    case mismatches do
      [] ->
        :ok

      _ ->
        Logger.warning(
          "[DBMigrator] pgvector dim drift detected. " <>
            "Configured dim = #{configured}; live dims = " <>
            Enum.map_join(mismatches, ", ", fn {t, d} -> "#{t}=#{d}" end) <>
            ". Auto-migrating: existing embeddings will be NULLified. " <>
            "Run `delfos scan --full` afterwards to repopulate."
        )

        migrated =
          Enum.map(mismatches, fn {table, _old_dim} ->
            migrate_table!(table, configured)
            table
          end)

        {:migrated, migrated}
    end
  end

  # ---- private --------------------------------------------------------------

  # Read the live vector dim by inspecting `pg_attribute`. Returns the
  # `atttypmod` (pgvector stores dim there for `vector(N)` columns) or
  # `nil` if the table/column doesn't exist.
  @spec pgvector_dim(String.t()) :: pos_integer() | nil
  defp pgvector_dim(table) do
    sql = """
    SELECT a.atttypmod
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_type t   ON t.oid = a.atttypid
    WHERE c.relname = $1
      AND a.attname = 'embedding'
      AND t.typname = 'vector'
      AND a.attnum > 0
      AND NOT a.attisdropped
    LIMIT 1
    """

    case Repo.query(sql, [table]) do
      {:ok, %{rows: [[dim]]}} when is_integer(dim) and dim > 0 -> dim
      _ -> nil
    end
  end

  # Apply ALTER TABLE for the given table. Drops the ivfflat index
  # first (it's dim-specific), nullifies embeddings (USING NULL to
  # avoid casts), then recreates the index with the new dim.
  @spec migrate_table!(String.t(), pos_integer()) :: :ok
  defp migrate_table!(table, new_dim) do
    {_table, index_name} = Enum.find(@tables, fn {t, _} -> t == table end)

    Repo.query!("DROP INDEX IF EXISTS #{index_name}")

    Repo.query!("ALTER TABLE #{table} ALTER COLUMN embedding TYPE vector(#{new_dim}) USING NULL")

    Repo.query!(
      "CREATE INDEX #{index_name} ON #{table} " <>
        "USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
    )

    :ok
  end
end
