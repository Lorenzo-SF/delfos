import Config

config :delfos, ecto_repos: [Delfos.Repo]
config :delfos, Delfos.Repo,
  database: System.get_env("DB_NAME", "delfos_dev"),
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  pool_size: 10


# ---------------------------------------------------------------------------
# Embedding — BGE-M3 Q4_K_M
# ---------------------------------------------------------------------------
# Ventajas sobre mxbai-embed-large:
#   - Multilingüe (87 idiomas): ideal para proyectos con docs/comentarios en
#     varios idiomas.
#   - Contexto de 8192 tokens vs 512 de mxbai → chunks más ricos sin truncar.
#   - Misma dimensión (1024d) → las migraciones existentes son compatibles.
#
# Arrancar con:
#   llama-server -m bge-m3-q4_k_m.gguf --port 9998 --embedding \
#     --threads 4 --batch-size 64 --ctx-size 2048 \
#     --mlock --no-mmap --flash-attn --host 127.0.0.1
# ---------------------------------------------------------------------------
config :delfos, :embedding,
  url: System.get_env("EMBED_URL", "http://127.0.0.1:9998"),
  model: System.get_env("EMBED_MODEL", "bge-m3"),
  api_key: System.get_env("API_KEY", "sk-local-dev"),
  dim: 1024,
  batch_size: 48,
  timeout_ms: 25_000

# ---------------------------------------------------------------------------
# LLM — dos modelos con responsabilidades distintas
# ---------------------------------------------------------------------------
# summarize_model (Qwen2.5-Coder-3B): rápido y eficiente para procesar
#   cientos de símbolos y generar resúmenes de 2-3 frases. Carga junto
#   al embed sin problemas de VRAM en una RTX 5080 16GB.
#   VRAM estimada: ~2.2 GB (Q4_K_M)
#
# llm_model (thinker Qwen2.5-14B): para query/explain donde la calidad
#   de razonamiento importa. Solo arranca bajo demanda.
#
# Arrancar Coder-3B:
#   llama-server -m qwen2.5-coder-3b-instruct-q4_k_m.gguf \
#     --port 8080 --threads 6 --batch-size 128 --ctx-size 8192 \
#     --mlock --no-mmap --flash-attn --host 127.0.0.1
#
# Arrancar thinker (14B) en puerto 8081 para query/explain:
#   MODEL_ID=thinker PORT=8081 bash llm-server.sh
# ---------------------------------------------------------------------------
config :delfos, :llm,
  url: System.get_env("LLAMA_URL", "http://127.0.0.1:8080"),
  model: System.get_env("LLM_MODEL", "Qwen2.5-Coder-3B-Instruct"),
  api_key: System.get_env("API_KEY", "sk-local-dev"),
  timeout_ms: 45_000,
  # max_tokens por caso de uso — NO usar un único valor global
  # resúmenes cortos y precisos
  summarize_max_tokens: 180,
  # explicaciones más completas
  explain_max_tokens: 600,
  # respuestas de consulta
  query_max_tokens: 512,
  # Modelo de mayor capacidad para query/explain (opcional, puerto 8081)
  thinker_url: System.get_env("THINKER_URL", "http://127.0.0.1:8081"),
  thinker_model: System.get_env("THINKER_MODEL", "thinker"),
  use_thinker_for_query: System.get_env("USE_THINKER", "false") == "true"

# ---------------------------------------------------------------------------
# Retrieval — pesos ajustados para BGE-M3 (mayor precisión vectorial)
# ---------------------------------------------------------------------------
config :delfos, :retrieval,
  vector_weight: 0.55,
  bm25_weight: 0.25,
  graph_weight: 0.20,
  top_k: 25,
  final_k: 7

# ---------------------------------------------------------------------------
# Indexing
# ---------------------------------------------------------------------------
config :delfos, :indexing,
  ignore_dirs: ~w(
    _build deps node_modules target .git dist coverage __pycache__
    .elixir_ls .dart_tool vendor Pods .gradle .venv build
    pubspec.lock package-lock.json yarn.lock
  ),
  max_chunk_tokens: 512

# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------
config :delfos, :analysis, churn_max_commits: 1000

import_config "#{config_env()}.exs"
