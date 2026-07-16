defmodule Delfos.Repo.Migrations.FixVectorDimTo1536 do
  use Ecto.Migration

  @moduledoc """
  Cambia el embedding column de vector(4096) a vector(1536) para que coincida
  con la salida real de Jina Code Embeddings 1.5B.

  Necesaria porque el modelo de embedding ha cambiado de Qwen3-Embedding-8B
  (dim=4096) a Jina Code Embeddings 1.5B (dim=1536). La dim 1536 permite
  además volver a usar índices HNSW (pgvector 0.8.4 permite HNSW hasta
  2000 dimensiones), mejorando la latencia de búsqueda vectorial.
  """

  def up do
    # Drop índices HNSW existentes (si los hay de la migración 20260628000001).
    # pgvector 0.8.4 limita ivfflat/HNSW a 2000 dims; con 1536 estamos dentro.
    execute "DROP INDEX IF EXISTS symbols_embedding_hnsw_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_hnsw_idx"
    execute "DROP INDEX IF EXISTS summaries_embedding_hnsw_idx"
    execute "DROP INDEX IF EXISTS symbols_embedding_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_idx"
    execute "DROP INDEX IF EXISTS summaries_embedding_idx"

    # Nullify embeddings existentes (dimensión 4096 incompatible con vector(1536))
    execute "UPDATE symbols   SET embedding = NULL"
    execute "UPDATE chunks    SET embedding = NULL"
    execute "UPDATE summaries SET embedding = NULL"

    # Cambiar dimensión 4096 → 1536.
    execute "ALTER TABLE symbols   ALTER COLUMN embedding TYPE vector(1536) USING NULL"
    execute "ALTER TABLE chunks    ALTER COLUMN embedding TYPE vector(1536) USING NULL"
    execute "ALTER TABLE summaries ALTER COLUMN embedding TYPE vector(1536) USING NULL"

    # Recrear índices HNSW (ahora caben en 1536 dims).
    execute """
    CREATE INDEX IF NOT EXISTS symbols_embedding_hnsw_idx
    ON symbols
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 200)
    """
    execute """
    CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw_idx
    ON chunks
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 200)
    """
    # Summaries son pocos, no necesitan índice HNSW.
  end

  def down do
    execute "DROP INDEX IF EXISTS symbols_embedding_hnsw_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_hnsw_idx"

    execute "UPDATE symbols   SET embedding = NULL"
    execute "UPDATE chunks    SET embedding = NULL"
    execute "UPDATE summaries SET embedding = NULL"

    execute "ALTER TABLE symbols   ALTER COLUMN embedding TYPE vector(4096) USING NULL"
    execute "ALTER TABLE chunks    ALTER COLUMN embedding TYPE vector(4096) USING NULL"
    execute "ALTER TABLE summaries ALTER COLUMN embedding TYPE vector(4096) USING NULL"
  end
end
