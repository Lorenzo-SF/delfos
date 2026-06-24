defmodule Delfos.Indexer.Watcher do
  @moduledoc """
  Vigila el sistema de archivos y re-indexa automáticamente los ficheros
  que cambian. Usa `file_system` (FSEvents/inotify/ReadDirectoryChangesW).

  Modos:
    :mcp — Activo siempre en modo MCP. Logs a stderr. Al terminar de
           re-indexar un archivo notifica a Delfos.MCP.IndexBroadcaster
           para que los clientes MCP reciban notifications/tools/list_changed.
    :cli — Activo solo si watch: true en config. Logs a stdout normal.

  Comportamiento:
    - Debounce de 1500ms por archivo (evita re-indexar durante guardado incremental)
    - Ignora directorios de ignore_dirs del config
    - Solo procesa extensiones soportadas por Dispatcher
    - Batch: acumula cambios en la ventana de debounce y los procesa juntos,
      emitiendo UNA SOLA notificación MCP por lote (no una por archivo)
  """

  use GenServer
  require Logger

  alias Delfos.Indexer.FileProcessor
  alias Delfos.Parsers.Dispatcher
  alias Delfos.Config.Manager
  alias Delfos.MCP.IndexBroadcaster

  @debounce_ms 1_500
  # Tiempo máximo que esperamos para acumular cambios en un lote
  @batch_window_ms 3_000

  @type mode :: :cli | :mcp
  @type state :: %{
          mode: mode(),
          project: Schema.Project.t() | nil,
          watcher: pid() | nil,
          pending: %{optional(String.t()) => reference()},
          batch_paths: [String.t()],
          batch_timer: reference() | nil,
          ignore_dirs: [String.t()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # Init
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, state()} | {:stop, term()}
  def init(opts) do
    mode = Keyword.get(opts, :mode, :cli)
    project = get_active_project()

    state = %{
      mode: mode,
      project: project,
      watcher: nil,
      # path => timer_ref (debounce individual por archivo)
      pending: %{},
      # paths acumulados para el siguiente lote MCP
      batch_paths: [],
      # timer_ref para emitir el lote
      batch_timer: nil,
      ignore_dirs: Manager.indexing()[:ignore_dirs] || []
    }

    if project do
      {:ok, watcher_pid} = FileSystem.start_link(dirs: [project.path])
      FileSystem.subscribe(watcher_pid)
      log(mode, :info, "Watcher activo: #{project.path}")
      {:ok, %{state | watcher: watcher_pid}}
    else
      log(mode, :warning, "Watcher: sin proyectos activos. Usa delfos init primero.")
      {:ok, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Eventos de file_system
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:file_event, _watcher, {path, events}}, state) do
    if should_process?(path, events, state) do
      # Cancelar timer previo para este path (debounce)
      state =
        case Map.get(state.pending, path) do
          nil ->
            state

          ref ->
            Process.cancel_timer(ref)
            %{state | pending: Map.delete(state.pending, path)}
        end

      ref = Process.send_after(self(), {:process_file, path}, @debounce_ms)
      {:noreply, %{state | pending: Map.put(state.pending, path, ref)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _watcher, :stop}, state) do
    log(state.mode, :info, "Watcher: file_system detenido")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Procesado de archivo (post-debounce)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:process_file, path}, state) do
    state = %{state | pending: Map.delete(state.pending, path)}

    if state.project && File.regular?(path) do
      rel_path = Path.relative_to(path, state.project.path)
      log(state.mode, :info, "↺ #{rel_path}")

      case File.read(path) do
        {:ok, content} ->
          project = state.project

          # Procesar en TaskSupervisor para no bloquear el Watcher
          Task.Supervisor.start_child(Delfos.TaskSupervisor, fn ->
            case FileProcessor.process_file(path, content, project) do
              {:ok, _} ->
                # Acumular en lote para notificación MCP
                GenServer.cast(__MODULE__, {:file_indexed, rel_path})

              {:error, reason} ->
                log(state.mode, :warning, "Error indexando #{rel_path}: #{inspect(reason)}")
            end
          end)

        {:error, reason} ->
          log(state.mode, :debug, "No pudo leer #{rel_path}: #{reason}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_batch, state) do
    flush_batch(state)
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Acumulación de lote para notificación MCP
  # ---------------------------------------------------------------------------

  @impl true
  def handle_cast({:file_indexed, rel_path}, state) do
    # Cancelar timer previo del lote si existe
    if state.batch_timer, do: Process.cancel_timer(state.batch_timer)

    new_batch = [rel_path | state.batch_paths]
    new_timer = Process.send_after(self(), :flush_batch, @batch_window_ms)

    {:noreply, %{state | batch_paths: new_batch, batch_timer: new_timer}}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp flush_batch(state) do
    if state.batch_paths != [] do
      IndexBroadcaster.notify_index_changed(Enum.reverse(state.batch_paths))
      log(state.mode, :info, "Lote re-indexado: #{length(state.batch_paths)} archivo(s)")
    end

    {:noreply, %{state | batch_paths: [], batch_timer: nil}}
  end

  defp should_process?(path, events, state) do
    Enum.any?(events, &(&1 in [:modified, :created, :renamed])) and
      Dispatcher.supported?(path) and
      not in_ignored_dir?(path, state.ignore_dirs, state.project)
  end

  defp in_ignored_dir?(path, ignore_dirs, project) do
    rel = if project, do: Path.relative_to(path, project.path), else: path
    parts = Path.split(rel)
    Enum.any?(ignore_dirs, &(&1 in parts))
  end

  defp get_active_project do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  rescue
    _ -> nil
  end

  # En modo :mcp los logs van a stderr para no contaminar stdout (canal MCP)
  defp log(:mcp, level, msg) do
    IO.puts(:standard_error, "[#{level |> to_string |> String.upcase()}] #{msg}")
  end

  defp log(_cli, :debug, msg), do: Logger.debug(msg)
  defp log(_cli, :info, msg), do: Logger.info(msg)
  defp log(_cli, :warning, msg), do: Logger.warning(msg)
end
