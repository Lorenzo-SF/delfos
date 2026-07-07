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

config :delfos, :embedding,
  url: System.get_env("EMBED_URL", "http://127.0.0.1:9998"),
  model: System.get_env("EMBED_MODEL", "bge-m3"),
  api_key: System.get_env("API_KEY", "sk-local-dev"),
  dim: 1024,
  batch_size: 48,
  timeout_ms: 25_000

config :delfos, :llm,
  url: System.get_env("LLAMA_URL", "http://127.0.0.1:8080"),
  model: System.get_env("LLM_MODEL", "Qwen2.5-Coder-3B-Instruct"),
  api_key: System.get_env("API_KEY", "sk-local-dev"),
  timeout_ms: 45_000,
  summarize_max_tokens: 180,
  explain_max_tokens: 600,
  query_max_tokens: 512,
  thinker_url: System.get_env("THINKER_URL", "http://127.0.0.1:8081"),
  thinker_model: System.get_env("THINKER_MODEL", "thinker"),
  use_thinker_for_query: System.get_env("USE_THINKER", "false") == "true"

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
