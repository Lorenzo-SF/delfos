import Config

config :delfos, Delfos.Repo,
  url: "postgresql://localhost/delfos_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :logger, level: :warning

config :delfos, Delfos.Repo,
  database: System.get_env("DB_NAME", "delfos_test"),
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  show_sensitive_data_on_connection_error: true

config :logger, :console, format: "[$level] $message\n"
