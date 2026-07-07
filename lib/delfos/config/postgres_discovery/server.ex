defmodule Delfos.Config.PostgresDiscovery.Server do
  @moduledoc """
  Connection info for a discovered PostgreSQL instance.

  `kind` is one of:
    * `:running`            — already up on `host:port`
    * `{:local, version}`   — installed on disk at `base/<version>`
    * `{:docker, name, image}` — running inside a Docker container
  """

  defstruct [:host, :port, :kind, :priority]

  @type t :: %__MODULE__{
          host: String.t(),
          port: pos_integer(),
          kind: :running | {:local, String.t()} | {:docker, String.t(), String.t()},
          priority: integer()
        }

  @doc false
  def new(host, port, kind, priority) do
    %__MODULE__{host: host, port: port, kind: kind, priority: priority}
  end
end
