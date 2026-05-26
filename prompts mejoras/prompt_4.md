📦 PROMPT 4: Watch Mode Incremental & MCP Server para Agentes
Contexto: Delfos requiere delfos scan manual. No hay integración con IDEs/agentes vía MCP. Falta sincronización en tiempo real y protocolo estándar para IA.
Objetivo: Implementar file_system watcher con debounce, reindexado selectivo, y MCP server JSON-RPC sobre stdio con tools: delfos_search, delfos_trace, delfos_context.
Requisitos Técnicos:
Delfos.Sync.Watcher con file_system + debounce 2s + hash diff
Reindexar solo archivos cambiados, actualizar edges afectados, checkpoint PostgreSQL
Delfos.MCP.Server implementando initialize, tools/list, tools/call
Tools MCP:
codegraph_search: query + kind + limit
codegraph_trace: BFS bidireccional con provenance
codegraph_context: AGENTS.md dinámico + symbol metadata + callers/callees
Health check /health para CLI y MCP
Modo offline: si LLM cae, MCP devuelve fallback: "bm25_only"
Pasos de Implementación:
# 1. Watcher
defmodule Delfos.Sync.Watcher do
  use GenServer
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  def init(opts) do
    FileSystem.start_link(dirs: [opts.project_path], name: :fs_watcher)
    {:ok, %{project: opts.project, debounce_ms: 2000, pending: %{}}}
  end
  def handle_info({:file_event, _, {path, events}}, state) do
    state = Map.update!(state, :pending, &Map.put(&1, path, DateTime.utc_now()))
    {:noreply, state}
  end
  def handle_info(:flush, state) do
    # reindex changed files, update graph, checkpoint
    {:noreply, %{state | pending: %{}}}
  end
  # debounce logic con Process.send_after
end

# 2. MCP Server (skeleton)
defmodule Delfos.MCP.Server do
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  def handle_cast({:stdio, json}, state) do
    req = Jason.decode!(json)
    case req["method"] do
      "initialize" -> reply(state, id: req["id"], result: %{capabilities: %{tools: %{}}})
      "tools/call" -> handle_tool_call(state, req)
    end
    {:noreply, state}
  end
end
Criterios de Aceptación:
delfos watch detecta cambio en lib/auth.ex, reindexa en <3s, no bloquea CLI
Agente (Cursor/Claude Desktop) llama tools/call → recibe JSON válido con símbolos
delfos trace devuelve path con provenance y code_snippet
MCP server soporta streaming: true para respuestas largas
Watcher usa inotify/fsevents nativo, no poll
Dependencias: :file_system ≥ 1.0, :jason, :gen_statem (para state machine MCP), :cowboy (opcional para HTTP fallback)