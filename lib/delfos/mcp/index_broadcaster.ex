defmodule Delfos.MCP.IndexBroadcaster do
  @moduledoc """
  Registry de clientes MCP activos y emisor de notificaciones de cambio de índice.

  Cuando el Watcher re-indexa un archivo notifica a este módulo.
  Este módulo envía `notifications/tools/list_changed` a todos los clientes
  MCP activos para que descarten su caché y usen datos frescos.

  Compatibilidad:
    - Claude Code: respeta list_changed, invalida caché de tools
    - Cursor: respeta list_changed
    - OpenCode: respeta list_changed
    - Otros: ignoran la notificación (inofensivo)

  En modo :cli este módulo arranca pero no tiene clientes registrados,
  por lo que notify/1 es un no-op.
  """

  use GenServer

  @type state :: %{clients: MapSet.t(pid())}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # API pública
  # ---------------------------------------------------------------------------

  @doc "Registra un PID de cliente MCP para recibir notificaciones."
  @spec register_client(pid()) :: :ok
  def register_client(pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:register, pid})
  end

  @doc "Notifies all registered MCP clients that the index changed."
  @spec notify_index_changed([String.t()]) :: :ok
  def notify_index_changed(paths) when is_list(paths) do
    GenServer.cast(__MODULE__, {:index_changed, paths})
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{clients: MapSet.new()}}
  end

  @impl true
  def handle_cast({:register, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | clients: MapSet.put(state.clients, pid)}}
  end

  def handle_cast({:index_changed, paths}, state) do
    notification =
      case Jason.encode(%{
             jsonrpc: "2.0",
             method: "notifications/tools/list_changed",
             params: %{
               _meta: %{
                 updated_paths: paths,
                 timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
               }
             }
           }) do
        {:ok, json} -> json
        {:error, _} -> nil
      end

    if notification do
      Enum.each(state.clients, fn pid ->
        send(pid, {:mcp_notification, notification})
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | clients: MapSet.delete(state.clients, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
