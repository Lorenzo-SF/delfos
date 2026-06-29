import Config

config :delfos, :env, :prod

config :delfos, Delfos.Repo,
  # `delfos_dev` is the default for both dev and prod. The previous
  # default `delfos_prod` surprised users who ran `mix gen` once
  # under MIX_ENV=prod and then saw a connection to a database
  # that didn't exist. Set DB_NAME=<real-name> to override.
  database: System.get_env("DB_NAME", "delfos_dev"),
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  pool_size: 5

config :logger, :console, format: "[$level] $message\n"
config :logger, level: :info
