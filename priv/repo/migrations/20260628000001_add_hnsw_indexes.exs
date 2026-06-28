defmodule Delfos.Repo.Migrations.AddHnswIndexes do
  use Ecto.Migration

  def up do
    execute """
    CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw_idx ON chunks
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 200)
    """

    execute """
    CREATE INDEX IF NOT EXISTS symbols_embedding_hnsw_idx ON symbols
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 200)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS chunks_embedding_hnsw_idx"
    execute "DROP INDEX IF EXISTS symbols_embedding_hnsw_idx"
  end
end
