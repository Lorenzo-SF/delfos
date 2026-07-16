import Config

config :delfos, ecto_repos: [Delfos.Repo]

config :delfos, Delfos.Repo,
  database: System.get_env("DB_NAME", "delfos_dev"),
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  pool_size: 10,
  types: Delfos.PostgrexTypes

# ---------------------------------------------------------------------------
# Embedding — Jina Code Embeddings 1.5B Q8_0
# ---------------------------------------------------------------------------
# Compile-time固定 NOT user-editable (ver `Delfos.Config.LLMDiscovery`):
#   - model:  "jina-code-embeddings-1.5b-Q8_0.gguf" (via llama-run embed)
#   - dim:    1536  (native dim; soporta Matryoshka hasta 1536)
#
# Jina Code Embeddings es un modelo especializado en código, 5× más ligero
# que Qwen3-Embedding-8B (1.6 GB vs 9 GB) con calidad de embeddings igual
# o mejor en benchmarks de código. Corre en CPU (NGL=0) para no competir
# con gpt-oss/coder por VRAM.
#
# Compile-time defaults, runtime-overridable via env vars (for the wrapper
# script `~/bin/llama-run`):
#   - url, api_key, ctx_size, n_gpu_layers, slot_dir, batch_size,
#     ubatch_size, pooling
#
# Arrancar con:
#   llama-run embed
# (Corre en CPU por defecto, sin competir por VRAM.)
# ---------------------------------------------------------------------------
config :delfos, :embedding,
  # ---- Compile-time固定 (changing these requires recompile) ----
  model: System.get_env("EMBED_MODEL", "embed"),
  dim: 1536,
  pooling: "last",
  # ---- Runtime defaults (overridable via env vars passed to llama-run) ----
  url: System.get_env("EMBED_URL", "http://127.0.0.1:9998"),
  api_key: System.get_env("API_KEY", "sk-local-dev-key"),
  ctx_size: 32_768,
  # n_gpu_layers: 99 = full GPU offload (fast embeddings, requires VRAM).
  # 0          = CPU-only (slower but no VRAM contention).
  # Default in config is "auto"; delfos decide via LlmDiscovery.
  n_gpu_layers:
    System.get_env("LLAMA_EMBED_NGL") ||
      if(System.get_env("LLAMA_EMBED_NGL_AUTO") == "auto",
        # resolved at runtime by LlmDiscovery
        do: "0",
        else: String.to_integer(System.get_env("LLAMA_EMBED_NGL", "99"))
      ),
  slot_dir: System.get_env("LLAMA_EMBED_SLOT_DIR", "/tmp/delfos-embeddings-cache"),
  batch_size: 512,
  ubatch_size: 512,
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
  url: System.get_env("LLAMA_URL", "http://127.0.0.1:9999"),
  model: System.get_env("LLM_MODEL", "gpt-oss"),
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
  thinker_url: System.get_env("THINKER_URL", "http://127.0.0.1:9999"),
  thinker_model: System.get_env("THINKER_MODEL", "gpt-oss"),
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
