import Config

config :delfos, ecto_repos: [Delfos.Repo]

config :delfos, :embedding,
  url: System.get_env("EMBED_URL", "http://127.0.0.1:9998"),
  model: System.get_env("EMBED_MODEL", "mxbai-embed-v1"),
  api_key: System.get_env("API_KEY", "sk-local-dev"),
  dim: String.to_integer(System.get_env("EMBED_DIM", "1024")),
  batch_size: 32,
  timeout_ms: 30_000

config :delfos, :llm,
  url: System.get_env("LLAMA_URL", "http://127.0.0.1:8080"),
  model: System.get_env("LLM_MODEL", "thinker"),
  api_key: System.get_env("API_KEY", "sk-local-dev"),
  timeout_ms: 60_000,
  max_tokens: 2048

config :delfos, :retrieval,
  vector_weight: 0.5,
  bm25_weight: 0.3,
  graph_weight: 0.2,
  top_k: 20,
  final_k: 5

config :delfos, :indexing,
  ignore_dirs: ~w(_build deps node_modules target .git dist coverage __pycache__ .elixir_ls),
  max_chunk_tokens: 512

config :delfos, :analysis,
  # número de commits a analizar en el historial git
  churn_max_commits: 1000

import_config "#{config_env()}.exs"
