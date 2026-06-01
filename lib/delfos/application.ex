defmodule Delfos.Application do
  @moduledoc """
  Árbol de supervisión de Delfos.

  Modos de arranque:
    - :cli   (default) — CLI interactivo. Watcher arranca si watch: true.
    - :mcp             — Servidor MCP stdio. Watcher SIEMPRE arranca, pero
                         usa stderr para logs (stdout es el canal MCP).

  El modo se fija antes de start_link vía:
    Application.put_env(:delfos, :mode, :mcp)
  """

  use Application

  @impl true
  def start(_type, _args) do
    mode = Application.get_env(:delfos, :mode, :cli)
    configure_logger_for_mode(mode)

    children =
      [
        Delfos.Repo,
        {Task.Supervisor, name: Delfos.TaskSupervisor},
        # siempre arranca; en :cli es no-op
        {Delfos.MCP.IndexBroadcaster, []}
      ] ++ watcher_children(mode)

    Supervisor.start_link(children, strategy: :one_for_one, name: Delfos.Supervisor)
  end

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

  # En modo MCP el watcher SIEMPRE arranca (indexado en tiempo real).
  defp watcher_children(:mcp) do
    [{Delfos.Indexer.Watcher, [mode: :mcp]}]
  end

  # En modo CLI sólo si watch: true en config.
  defp watcher_children(_cli) do
    if Application.get_env(:delfos, :watch, false) do
      [{Delfos.Indexer.Watcher, [mode: :cli]}]
    else
      []
    end
  end
end
