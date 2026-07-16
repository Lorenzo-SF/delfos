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
# Models — directorio por defecto donde viven los GGUF
# ---------------------------------------------------------------------------
# Resolución única para todos los modelos (embed + llm +
# summarize). Override en runtime via:
#   - env var GGUF_DIR
#   - 'delfos config set models gguf_dir /custom/path'
# ---------------------------------------------------------------------------
config :delfos, :models,
  gguf_dir:
    System.get_env(
      "GGUF_DIR",
      Path.join([System.get_env("HOME", "/root"), "models", "gguf"])
    )

# ---------------------------------------------------------------------------
# Embedding — Jina Code Embeddings 1.5B Q8_0
# ---------------------------------------------------------------------------
# Compile-time固定 NOT user-editable (ver `Delfos.Config.LLMDiscovery`):
#   - model:  FILENAME (with .gguf extension) resolved against
#             `:models.gguf_dir`. NOT an alias — the file MUST exist
#             on disk for VRAM estimation to work.
#   - dim:    1536  (native dim; soporta Matryoshka hasta 1536)
#
# `LLAMA_EMBED_MODEL` env var is the SAME one read by `~/bin/llama-run`
# (the wrapper script), so changing it once propagates to both systems.
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
  model: System.get_env("LLAMA_EMBED_MODEL", "jina-code-embeddings-1.5b-Q8_0.gguf"),
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
# LLM — UN solo modelo (gpt-oss-20b) para chat, query y explain
# ---------------------------------------------------------------------------
# Compile-time固定 (ver `Delfos.Config.LLMDiscovery`):
#   - model:  FILENAME (with .gguf extension) resolved against
#             `:models.gguf_dir`. NOT an alias. Loaded by `llama-run gpt-oss`.
#
# `LLAMA_LLM_MODEL` env var mirrors `LLAMA_EMBED_MODEL`: the same env var
# is read by `~/bin/llama-run` (which sets `MODEL_gpt_oss_GGUF`).
#
# Arrancar con:
#   llama-run gpt-oss
# ---------------------------------------------------------------------------
config :delfos, :llm,
  # ---- Compile-time固定 ----
  model: System.get_env("LLAMA_LLM_MODEL", "gpt-oss-20b-UD-Q8_K_XL.gguf"),
  # ---- Runtime defaults (overridable via env vars / runtime JSON) ----
  url: System.get_env("LLAMA_URL", "http://127.0.0.1:9999"),
  api_key: System.get_env("API_KEY", "sk-local-dev"),
  timeout_ms: 45_000,
  # max_tokens por caso de uso — NO usar un único valor global
  # resúmenes cortos y precisos
  summarize_max_tokens: 180,
  # explicaciones más completas
  explain_max_tokens: 600,
  # respuestas de consulta
  query_max_tokens: 512

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
