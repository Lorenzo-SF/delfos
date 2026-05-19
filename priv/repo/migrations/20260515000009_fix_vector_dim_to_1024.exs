defmodule Delfos.Repo.Migrations.FixVectorDimTo1024 do
  @moduledoc """
  Migración correctiva: cambia el tamaño de las columnas vector de 768 a 1024
  para alinearlas con mxbai-embed-large-v1 que produce vectores de 1024 dims.

  Solo es necesaria si la DB ya fue creada con las migraciones originales.
  En una DB nueva las migraciones 000003, 000004 y 000005 ya usan 1024.
  """
  use Ecto.Migration

  def up do
    # Primero eliminar los índices ivfflat (no soportan ALTER COLUMN)
    execute "DROP INDEX IF EXISTS symbols_embedding_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_idx"
    execute "DROP INDEX IF EXISTS summaries_embedding_idx"

    # Limpiar los embeddings existentes (incompatibles con el nuevo tamaño)
    execute "UPDATE symbols SET embedding = NULL"
    execute "UPDATE chunks SET embedding = NULL"
    execute "UPDATE summaries SET embedding = NULL"

    # Cambiar el tipo de columna
    execute "ALTER TABLE symbols ALTER COLUMN embedding TYPE vector(1024)"
    execute "ALTER TABLE chunks ALTER COLUMN embedding TYPE vector(1024)"
    execute "ALTER TABLE summaries ALTER COLUMN embedding TYPE vector(1024)"

    # Recrear índices
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

    # También corregir el índice FTS de symbols y chunks si usaba 'spanish'
    execute "DROP INDEX IF EXISTS symbols_fts_idx"
    execute "DROP INDEX IF EXISTS chunks_fts_idx"

    execute """
      CREATE INDEX symbols_fts_idx ON symbols
      USING gin(to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(content,'')))
    """
    execute """
      CREATE INDEX chunks_fts_idx ON chunks
      USING gin(to_tsvector('simple', content))
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS symbols_embedding_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_idx"
    execute "DROP INDEX IF EXISTS summaries_embedding_idx"

    execute "UPDATE symbols SET embedding = NULL"
    execute "UPDATE chunks SET embedding = NULL"
    execute "UPDATE summaries SET embedding = NULL"

    execute "ALTER TABLE symbols ALTER COLUMN embedding TYPE vector(768)"
    execute "ALTER TABLE chunks ALTER COLUMN embedding TYPE vector(768)"
    execute "ALTER TABLE summaries ALTER COLUMN embedding TYPE vector(768)"

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
  end
end
