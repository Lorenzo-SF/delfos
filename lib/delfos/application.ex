defmodule Delfos.Application do
  @moduledoc """
  Supervision tree for Delfos.

  Startup modes:
    - `:cli` (default) — interactive CLI. The Watcher starts only if
      `watch: true` is configured.
    - `:mcp` — MCP stdio server. The Watcher ALWAYS starts, but logs
      go to stderr (stdout is the MCP channel).

  The mode is set before `start_link` via:
      Application.put_env(:delfos, :mode, :mcp)
  """

  use Application

  @required_env_vars %{
    "DB_NAME" => "PostgreSQL database name",
    "DB_USER" => "PostgreSQL username",
    "DB_PASS" => "PostgreSQL password"
  }

  @impl true
  def start(type, _args) do
    mode = Application.get_env(:delfos, :mode, :cli)

    with :ok <- validate_in_prod(type) do
      configure_logger_for_mode(mode)
      Delfos.Syntax.Registry.register_all()

      children =
        [
          Delfos.Repo,
          {Task.Supervisor, name: Delfos.TaskSupervisor},
          {Delfos.MCP.IndexBroadcaster, []}
        ] ++ watcher_children(mode) ++ health_children(mode)

      Supervisor.start_link(children, strategy: :one_for_one, name: Delfos.Supervisor)
    end
  end

  @impl true
  def stop(_state) do
    :ok
  rescue
    _ -> :ok
  end

  # Only validate env vars in production.
  # Dev and test environments provide sensible defaults.
  defp validate_in_prod(:normal) do
    if Mix.env() == :prod do
      missing =
        Enum.reduce_while(@required_env_vars, [], fn {var, _desc}, acc ->
          case System.get_env(var) do
            nil -> {:cont, [var | acc]}
            "" -> {:cont, [var | acc]}
            _ -> {:cont, acc}
          end
        end)

      if missing == [],
        do: :ok,
        else: {:error, "Missing required environment variables: #{Enum.join(missing, ", ")}"}
    else
      :ok
    end
  end

  defp validate_in_prod(_), do: :ok

  # ---------------------------------------------------------------------------
  # Logger — en modo MCP redirigir a stderr para no contaminar stdout
  # ---------------------------------------------------------------------------

  defp configure_logger_for_mode(:mcp) do
    Logger.configure_backend(:console, device: :standard_error)
    Logger.configure(level: :warning)
  end

  defp configure_logger_for_mode(_), do: :ok

  # ---------------------------------------------------------------------------
  # Watcher
  # ---------------------------------------------------------------------------

  defp watcher_children(:mcp) do
    [{Delfos.Indexer.Watcher, [mode: :mcp]}]
  end

  defp watcher_children(_cli) do
    if Application.get_env(:delfos, :watch, false) do
      [{Delfos.Indexer.Watcher, [mode: :cli]}]
    else
      []
    end
  end

  # ---------------------------------------------------------------------------
  # Health check (Botica)
  # ---------------------------------------------------------------------------

  defp health_children(_mode) do
    if Application.get_env(:delfos, :health_check, false) do
      [{Delfos.Health, []}]
    else
      []
    end
  end
end
