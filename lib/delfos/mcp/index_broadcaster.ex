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

  La gestión de suscriptores delega en `Arrea.Subscribers` (M2).
  """

  use GenServer

  alias Arrea.Subscribers

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
    GenServer.call(__MODULE__, {:register, pid})
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
  def handle_call({:register, pid}, _from, state) do
    {:reply, :ok, %{state | clients: Subscribers.subscribe(state.clients, pid)}}
  end

  @impl true
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

    clients =
      if notification do
        Subscribers.broadcast(state.clients, {:mcp_notification, notification})
      else
        state.clients
      end

    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | clients: Subscribers.handle_down(state.clients, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
