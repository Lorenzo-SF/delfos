defmodule Delfos.Repo.Migrations.FixVectorDimTo1024 do
  use Ecto.Migration

  @doc """
  Migración correctiva para bases de datos existentes con vector(768) o
  FTS con 'spanish'. Actualiza todo a vector(1024) y 'simple'.

  Solo necesaria si tienes una DB de sesiones anteriores a v0.4.
  """
  def up do
    # Eliminar índices ivfflat (incompatibles con cambio de dimensión)
    execute "DROP INDEX IF EXISTS symbols_embedding_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_idx"
    execute "DROP INDEX IF EXISTS summaries_embedding_idx"
    execute "DROP INDEX IF EXISTS symbols_fts_idx"
    execute "DROP INDEX IF EXISTS chunks_fts_idx"

    # Nullificar embeddings incompatibles con la nueva dimensión
    execute "UPDATE symbols  SET embedding = NULL"
    execute "UPDATE chunks   SET embedding = NULL"
    execute "UPDATE summaries SET embedding = NULL"

    # Cambiar dimensión de vector
    execute "ALTER TABLE symbols   ALTER COLUMN embedding TYPE vector(1024) USING NULL"
    execute "ALTER TABLE chunks    ALTER COLUMN embedding TYPE vector(1024) USING NULL"
    execute "ALTER TABLE summaries ALTER COLUMN embedding TYPE vector(1024) USING NULL"

    # Recrear índices con dimensión y configuración correctas
    execute """
      CREATE INDEX symbols_embedding_idx ON symbols
      USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    """
    execute """
      CREATE INDEX chunks_embedding_idx ON chunks
      USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    """
    execute """
      CREATE INDEX summaries_embedding_idx ON summaries
      USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    """

    # Recrear FTS con 'simple' (multilingüe)
    execute """
      CREATE INDEX symbols_fts_idx ON symbols
      USING gin(to_tsvector('simple',
        coalesce(name,'') || ' ' || coalesce(qualified_name,'') || ' ' || coalesce(content,'')))
    """
    execute """
      CREATE INDEX chunks_fts_idx ON chunks
      USING gin(to_tsvector('simple', content))
    """
  end

  def down do
    # No hay rollback útil aquí: los embeddings ya fueron nullificados
    :ok
  end
end
