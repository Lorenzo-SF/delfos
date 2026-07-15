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
# Embedding — Qwen3-Embedding-8B Q8_0
# ---------------------------------------------------------------------------
# Compile-time固定 NOT user-editable (ver `Delfos.Config.LLMDiscovery`):
#   - model:  "Qwen3-Embedding-8B-Q8_0.gguf"
#   - dim:    4096  (matryoshka-capable; this is the full native dim)
#
# Compile-time defaults, runtime-overridable via env vars (for the wrapper
# script `~/bin/llama-run`):
#   - url, api_key, ctx_size, n_gpu_layers, slot_dir, batch_size,
#     ubatch_size, pooling
#
# Why Qwen3-Embedding-8B:
#   - Top-1 open-weight on MTEB-Code and BEIR among ≤8B models.
#   - 32K context, code-tuned, multilingual.
#   - Native dim = 4096 — matches our existing pgvector schema. No migration.
#
# What delfos manages automatically (see `LlmDiscovery.recommended_embed_ngl/0`):
#   - NGL=99 (full GPU offload) when:
#       * chat provider is NOT local (no VRAM contention with gpt-oss), OR
#       * delfos decided to nudge the user toward full-GPU embedding.
#   - NGL=0 (CPU-only) when:
#       * chat provider IS local and the chat model is heavy (e.g. gpt-oss
#         20B at ~13 GB) — to avoid OOM on a single GPU.
#
# Override at runtime with: LLAMA_EMBED_NGL=33 bash ~/bin/llama-run embed
#
# Arrancar con:
#   LLAMA_EMBED_NGL=99 bash ~/bin/llama-run embed
# (El wrapper ya lee config.exs mediante env vars inyectadas por `mix`
# cuando delfos arranca el server, o pasadas a mano si lo arrancas tú.)
# ---------------------------------------------------------------------------
config :delfos, :embedding,
  # ---- Compile-time固定 (changing these requires recompile) ----
  # Filename case matches the actual file on disk
  # (~/models/gguf/Qwen3-Embedding-8B-q8_0.gguf, lowercase `q8_0`).
  model: System.get_env("EMBED_MODEL", "Qwen3-Embedding-8B-q8_0.gguf"),
  dim: 4096,
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
        do: nil,
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
