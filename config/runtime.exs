import Config

config :delfos, :env, :prod

config :delfos, Delfos.Repo,
  database: System.get_env("DB_NAME", "delfos_prod"),
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  pool_size: 5,
  types: Delfos.PostgrexTypes

# Embedding + LLM model, dim, ctx_size, n_gpu_layers, slot_dir,
# batch_size, ubatch_size, pooling — all COMPILE-TIME固定 in
# `config/config.exs`. They are NOT declared here on purpose: any
# re-declaration in `runtime.exs` would re-merge at boot and produce
# a Keyword-list that differs in key ORDER from the compile-time
# one, triggering Elixir's `validate_compile_env` warning and
# crashing the release.
#
# Runtime overrides of the *operational* knobs (where the servers
# run, auth, timeouts, retrieval weights) live in
# `Delfos.Config.Manager` — it reads from `~/.config/delfos/config.json`
# and applies env vars (EMBED_URL, LLAMA_URL, etc.) at call time,
# without touching the compile-time `:delfos, :embedding` /
# `:delfos, :llm` keys.
#
# See `Delfos.DBMigrator`, `Delfos.Config.LLMDiscovery` and
# `config/config.exs` for the embed-and-LLM config surface.

config :delfos, :retrieval,
  vector_weight: 0.55,
  bm25_weight: 0.25,
  graph_weight: 0.20,
  top_k: 25,
  final_k: 7

config :delfos, :indexing,
  ignore_dirs: ~w(
    _build deps node_modules target .git dist coverage __pycache__
    .elixir_ls .dart_tool vendor Pods .gradle .venv build
    pubspec.lock package-lock.json yarn.lock
  ),
  max_chunk_tokens: 512

config :delfos, :analysis, churn_max_commits: 1000

config :logger, :console, format: "[$level] $message\n"
config :logger, level: :info
