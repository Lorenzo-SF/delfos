import Config

config :delfos, Delfos.Repo,
  url: "postgresql://localhost/delfos_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :logger, level: :warning
