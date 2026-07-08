defmodule Delfos.Repo.Migrations.FixVectorDimTo4096 do
  use Ecto.Migration

  @moduledoc """
  Cambia el embedding column de vector(1024) a vector(4096) para que coincida
  con la salida real de Qwen3-Embedding-8B. Análoga a 20260515000009 pero 4096.

  Necesaria porque el modelo de embedding configurado por defecto en
  `~/bin/register-local-llms` (Qwen3-Embedding-8B) devuelve vectores de
  4096 dimensiones, no de 1024. El schema pgvector anterior era 1024,
  heredado de cuando se pensaba usar BGE-M3 o mxbai-embed-large. El
  comentario histórico en register-local-llms que decía "llama.cpp can be
  configured to truncate to 1024" resultó ser incorrecto para este rev
  de llama.cpp server.
  """

  def up do
    # Drop TODOS los índices existentes sobre la columna embedding.
    # También se auto-dropean al ALTER TYPE, pero explícito es más
    # claro y evita race conditions.
    #
    # IMPORTANTE: pgvector 0.8.4 limita ivfflat y HNSW a un máximo de
    # 2000 dimensiones. Como Qwen3-Embedding-8B produce 4096-dim, no
    # podemos recrear NINGÚN índice ANN. Las búsquedas vectoriales
    # serán sequential scans sobre la columna completa.
    # Para el tamaño esperado del proyecto Delfos (~367 símbolos,
    # ~4000 chunks), esto es aceptable: ~5-7MB de datos vectoriales
    # y latencia de query ~50-100ms. Cuando crezcamos más allá de
    # ~50k chunks, considerar:
    #   a) Reducir dimensión con PCA post-embed
    #   b) Upgrade a pgvector 0.9+ (que sube el límite a 4096 para HNSW)
    #   c) Cambiar a un modelo embed de ≤2000 dims (mxbai, BGE-large)
    execute "DROP INDEX IF EXISTS symbols_embedding_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_idx"
    execute "DROP INDEX IF EXISTS summaries_embedding_idx"
    execute "DROP INDEX IF EXISTS chunks_embedding_hnsw_idx"
    execute "DROP INDEX IF EXISTS symbols_embedding_hnsw_idx"

    # Nullify embeddings (dimensión incompatible con vector(4096)).
    # USING NULL descarta los valores antiguos en vez de intentar
    # convertirlos.
    execute "UPDATE symbols   SET embedding = NULL"
    execute "UPDATE chunks    SET embedding = NULL"
    execute "UPDATE summaries SET embedding = NULL"

    # Cambiar dimensión 1024 → 4096.
    execute "ALTER TABLE symbols   ALTER COLUMN embedding TYPE vector(4096) USING NULL"
    execute "ALTER TABLE chunks    ALTER COLUMN embedding TYPE vector(4096) USING NULL"
    execute "ALTER TABLE summaries ALTER COLUMN embedding TYPE vector(4096) USING NULL"

    # NO recreamos índices. La búsqueda vectorial usará sequential scan.
    # El HNSW migration (20260628000001) queda inefectiva para esta dim.
    # Los operadores <=> y <-> siguen funcionando, simplemente sin índice.
  end

  def down, do: :ok
end