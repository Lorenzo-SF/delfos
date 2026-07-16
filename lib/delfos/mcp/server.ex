defmodule Delfos.MCP.Server do
  @moduledoc """
  Servidor MCP (Model Context Protocol) con transporte stdio.

  Protocolo: JSON-RPC 2.0 sobre stdin/stdout.
  Versión:   2024-11-05

  Herramientas:
    delfos_search   — búsqueda híbrida (vector + BM25 + grafo)
    delfos_symbol   — detalles completos de un símbolo con resumen LLM
    delfos_context  — contexto compacto para una tarea
    delfos_callers  — quién llama a un símbolo
    delfos_callees  — qué llama un símbolo
    delfos_impact   — análisis de impacto BFS
    delfos_audit    — métricas de deuda del proyecto o archivo
    delfos_files    — estructura de archivos indexados

  Cada herramienta también responde a su nombre corto
  (ej. `search` para `delfos_search`).

  Indexado en tiempo real:
    El Watcher re-indexa archivos modificados en background.
    Al completar un lote de re-indexado, IndexBroadcaster envía
    notifications/tools/list_changed a este proceso, que lo reenvía
    al cliente MCP por stdout.

  Tool execution is wrapped in a timeout (default 30s) y try/rescue so
  that an exception in a tool handler does not crash the whole server.
  Clients receive `isError: true` with a structured message instead.

  Arrancar:
    delfos mcp
  """

  require Logger

  alias Delfos.MCP.{Tools, IndexBroadcaster}
  alias Delfos.Statistics

  @protocol_version "2024-11-05"
  @server_name "delfos"
  @server_version Delfos.version()

  # Max time a tool handler may take. Past this we return isError to the
  # client and the tool Task is killed. Tuned for LLM-backed tools
  # (summarize, explain) which can occasionally stall on cold caches.
  @tool_timeout_ms 30_000

  @doc false
  def tool_timeout_ms, do: @tool_timeout_ms

  @doc "MCP protocol version this server implements."
  def protocol_version, do: @protocol_version

  @doc "Server name reported in the `initialize` response."
  def server_name, do: @server_name

  @doc "Server version reported in the `initialize` response."
  def server_version, do: @server_version

  def start do
    # Splash UI: Pulsar animation while NIFs + supervision tree start up.
    # Stderr is non-blocking (Logger.configure above routes to :stdio in MCP mode),
    # so the splash renders immediately and disappears cleanly when the
    # server enters its receive loop. Skipped when stderr is not a TTY
    # (CI, piped output) to avoid spamming non-interactive sessions.
    print_startup_splash()

    # Configurar modo MCP antes de arrancar la app.
    # Re-configurar el Logger aunque la app ya estuviera iniciada
    # (modo CLI previo en la misma sesión → logger contaminaría stdout).
    Application.put_env(:delfos, :mode, :mcp)
    Delfos.Application.configure_logger_for_mode(:mcp)
    Application.ensure_all_started(:delfos)

    # v2.6.0: probe the tree-sitter NIF BEFORE entering the receive loop.
    # Pre-v2.6.0, the server started fine even with a missing .so and
    # silently fell back to regex parsing — producing wrong results with
    # no error to the MCP client. Now we abort cleanly (non-zero exit
    # code via Delfos.CLI.Abort) so the client knows the server failed.
    # Users who explicitly want regex fallback can set
    # `:delfos, :regex_fallback, true` in config.
    unless Delfos.Parsers.NIFStatus.acceptable?() do
      IO.puts(
        :stderr,
        "\n  #{IO.ANSI.red()}✗#{IO.ANSI.reset()} Delfos MCP server cannot start: " <>
          "the tree-sitter NIF failed to load.\n" <>
          "    Reason: missing or unloadable libtree_sitter_nif.so.\n" <>
          "    Fix:    rebuild the release (`mix batamanta`) or\n" <>
          "            run `mix deps.compile tree_sitter rustler`.\n" <>
          "    Alt:    set `regex_fallback: true` in delfos config to\n" <>
          "            accept degraded regex parsing instead of aborting.\n"
      )

      raise Delfos.CLI.Abort,
        message: "tree-sitter NIF not loaded and no regex_fallback config",
        code: 78
    end

    print_startup_ready()

    # Registrar este proceso para recibir notificaciones de cambio de índice
    IndexBroadcaster.register_client(self())

    # Lanzar proceso separado que lee stdin (bloqueante) y envía mensajes
    # al loop principal. Esto evita que IO.gets bloquee el receive loop
    # y permite procesar notificaciones en tiempo real.
    #
    # IMPORTANTE: capturamos `self()` ANTES del spawn_link y lo pasamos
    # al reader como argumento. Antes, el reader hacía
    #   Process.whereis(Delfos.MCP.Server) || self()
    # que siempre caía al fallback `self()` porque el módulo Delfos.MCP.Server
    # nunca se registra como proceso (no hay start_link / Process.register
    # en ninguna ruta). Resultado: mensajes iban al propio reader, nunca
    # llegaban al loop principal, MCP server no respondía a tools/list.
    main_pid = self()
    spawn_link(fn -> stdin_reader(main_pid) end)

    Logger.info("Delfos MCP v#{@server_version} iniciado")

    initial_state = %{
      initialized: false,
      # tools/call asíncronos:
      # %{task_ref => %{id, timer, task_pid, project, tool_name, started_at}}
      pending_tools: %{}
    }

    loop(initial_state)
  end

  # ---------------------------------------------------------------------------
  # Lector de stdin en proceso separado
  # ---------------------------------------------------------------------------

  defp stdin_reader(main_pid) do
    # Todo el cuerpo del reader está envuelto en try/rescue para que
    # NUNCA crashee el proceso (R4). Si IO.gets lanza una excepción
    # (stdin cerrado abruptamente, EIO, etc.), lo capturamos y
    # notificamos al main.
    read_line(main_pid)
  rescue
    e ->
      Logger.error("MCP stdin reader crashed: #{Exception.message(e)}")
      send(main_pid, {:stdin, :eof})
  catch
    :exit, reason ->
      Logger.error("MCP stdin reader exited: #{inspect(reason)}")
      send(main_pid, {:stdin, :eof})
  end

  defp read_line(main_pid) do
    case IO.gets("") do
      :eof ->
        send(main_pid, {:stdin, :eof})

      {:error, reason} ->
        send(main_pid, {:stdin, {:error, reason}})

      line when is_binary(line) ->
        trimmed = String.trim(line)
        send(main_pid, {:stdin, trimmed})
        read_line(main_pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Loop principal (mensajes recibidos del reader y notificaciones)
  # ---------------------------------------------------------------------------

  defp loop(state) do
    receive do
      {:stdin, :eof} ->
        Logger.info("MCP: EOF, cerrando")
        shutdown_pending_tools(state.pending_tools)
        :ok

      {:stdin, {:error, reason}} ->
        Logger.error("MCP stdin: #{inspect(reason)}")
        :ok

      {:stdin, ""} ->
        loop(state)

      {:stdin, line} ->
        case Jason.decode(line) do
          {:ok, msg} ->
            {response, new_state} = handle_message(msg, state)
            if response, do: send_response(response)
            loop(new_state)

          {:error, _} ->
            send_error(nil, -32700, "Parse error")
            loop(state)
        end

      {:index_updated, _project_id} ->
        # Reenviar notificación al cliente MCP
        send_notification("notifications/tools/list_changed", %{})
        loop(state)

      # Resultado de un tools/call asíncrono (ref de Task → ref única)
      {ref, result} when is_reference(ref) ->
        case Map.pop(state.pending_tools, ref) do
          {nil, _} ->
            # Ref no reconocida (posiblemente ya timeout'eada) — ignorar
            loop(state)

          {pending, rest} ->
            Process.cancel_timer(pending.timer)
            duration_ms = elapsed_ms(pending.started_at)

            Statistics.record_call_async(
              pending.project,
              pending.tool_name,
              result,
              duration_ms
            )

            send_response(build_tool_response(pending.id, result))
            loop(%{state | pending_tools: rest})
        end

      # Timeout de un tools/call
      {:tool_timeout, _id, ref} ->
        case Map.pop(state.pending_tools, ref) do
          {nil, _rest} ->
            loop(state)

          {pending, rest} ->
            # Matar el task si aún corre
            try do
              Task.Supervisor.terminate_child(Delfos.TaskSupervisor, pending.task_pid)
            rescue
              _ -> :ok
            catch
              _, _ -> :ok
            end

            timeout_result = {:error, "Tool timed out after #{@tool_timeout_ms}ms"}

            Statistics.record_call_async(
              pending.project,
              pending.tool_name,
              timeout_result,
              elapsed_ms(pending.started_at),
              :timeout
            )

            send_response(build_tool_response(pending.id, timeout_result))
            loop(%{state | pending_tools: rest})
        end

      _other ->
        loop(state)
    end
  end

  defp shutdown_pending_tools(pending) when map_size(pending) == 0, do: :ok

  defp shutdown_pending_tools(pending) do
    for {_ref, tool} <- pending do
      Process.cancel_timer(tool.timer)

      try do
        Task.Supervisor.terminate_child(Delfos.TaskSupervisor, tool.task_pid)
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Handlers de mensajes MCP
  # ---------------------------------------------------------------------------

  defp handle_message(%{"method" => "initialize", "id" => id}, state) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        protocolVersion: @protocol_version,
        serverInfo: %{name: @server_name, version: @server_version},
        capabilities: %{
          tools: %{},
          experimental: %{
            indexing: %{
              realtime: true,
              notification: "notifications/tools/list_changed"
            }
          }
        }
      }
    }

    {response, %{state | initialized: true}}
  end

  defp handle_message(%{"method" => "notifications/initialized"}, state) do
    {nil, state}
  end

  defp handle_message(%{"method" => "tools/list", "id" => id}, state) do
    {%{jsonrpc: "2.0", id: id, result: %{tools: tool_definitions()}}, state}
  end

  defp handle_message(%{"method" => "ping", "id" => id}, state) do
    {%{jsonrpc: "2.0", id: id, result: %{}}, state}
  end

  defp handle_message(%{"method" => "tools/call", "id" => id, "params" => params}, state) do
    raw_name = params["name"]
    tool_name = normalize_tool_name(raw_name)
    arguments = params["arguments"] || %{}
    project = get_project()
    started_at = System.monotonic_time(:millisecond)

    # Lanzamos la tool en un Task supervisado. NO hacemos Task.await —
    # el resultado llega como mensaje al loop, permitiendo procesar
    # otras requests y notificaciones mientras la tool se ejecuta (R1).
    task =
      Task.Supervisor.async_nolink(Delfos.TaskSupervisor, fn ->
        try do
          dispatch_tool(tool_name, project, arguments)
        rescue
          e -> {:error, "Tool #{raw_name} raised: #{Exception.message(e)}"}
        catch
          :exit, reason -> {:error, "Tool #{raw_name} crashed: #{inspect(reason)}"}
          kind, reason -> {:error, "Tool #{raw_name} #{kind}: #{inspect(reason)}"}
        end
      end)

    timer = Process.send_after(self(), {:tool_timeout, id, task.ref}, @tool_timeout_ms)

    pending = %{
      id: id,
      timer: timer,
      task_pid: task.pid,
      project: project,
      tool_name: tool_name,
      started_at: started_at
    }

    {nil, %{state | pending_tools: Map.put(state.pending_tools, task.ref, pending)}}
  end

  defp handle_message(%{"id" => id}, state) do
    {%{jsonrpc: "2.0", id: id, error: %{code: -32601, message: "Method not found"}}, state}
  end

  defp handle_message(_, state), do: {nil, state}

  # ---------------------------------------------------------------------------
  # Normalización de nombres de herramientas
  #
  # opencode antepone el nombre del servidor como prefijo ("delfos_")
  # a los nombres de las herramientas. Si el nombre de la herramienta ya
  # empieza con "delfos_", opencode lo duplica: "delfos_delfos_search".
  # Esta función normaliza eliminando el prefijo duplicado y también
  # acepta versiones cortas (sin "delfos_").
  # ---------------------------------------------------------------------------

  def normalize_tool_name(name) do
    name
    # opencode duplica el prefijo: delfos_delfos_search → delfos_search
    |> then(fn n ->
      if String.starts_with?(n, "delfos_delfos_"),
        do: String.replace_prefix(n, "delfos_delfos_", "delfos_"),
        else: n
    end)
    # Si aún así no es un nombre conocido, probar con/sin prefijo
    |> then(fn n ->
      case n do
        "delfos_search" -> n
        "delfos_symbol" -> n
        "delfos_context" -> n
        "delfos_callers" -> n
        "delfos_callees" -> n
        "delfos_impact" -> n
        "delfos_audit" -> n
        "delfos_files" -> n
        # Si es un nombre corto, añadir prefijo
        "search" -> "delfos_search"
        "symbol" -> "delfos_symbol"
        "context" -> "delfos_context"
        "callers" -> "delfos_callers"
        "callees" -> "delfos_callees"
        "impact" -> "delfos_impact"
        "audit" -> "delfos_audit"
        "files" -> "delfos_files"
        # Si no es ningún nombre conocido, dejarlo como está
        _ -> n
      end
    end)
  end

  @doc false
  def dispatch_tool(tool_name, project, arguments) do
    case tool_name do
      "delfos_search" ->
        Tools.search(project, arguments)

      "delfos_symbol" ->
        Tools.symbol(project, arguments)

      "delfos_context" ->
        Tools.context(project, arguments)

      "delfos_callers" ->
        Tools.callers(project, arguments)

      "delfos_callees" ->
        Tools.callees(project, arguments)

      "delfos_impact" ->
        Tools.impact(project, arguments)

      "delfos_audit" ->
        Tools.audit(project, arguments)

      "delfos_files" ->
        Tools.files(project, arguments)

      _ ->
        {:error,
         "Herramienta desconocida: #{tool_name}. " <>
           "Herramientas disponibles: search, symbol, context, callers, callees, impact, audit, files"}
    end
  end

  @doc false
  def build_tool_response(id, result) do
    case result do
      {:ok, content} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{content: [%{type: "text", text: content}]}
        }

      {:error, reason} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{
            content: [%{type: "text", text: "Error: #{reason}"}],
            isError: true
          }
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Tool definitions
  # ---------------------------------------------------------------------------

  defp tool_definitions do
    [
      %{
        name: "delfos_search",
        description: """
        Búsqueda híbrida en el índice de Delfos (vector semántico + BM25 + grafo).
        El índice se actualiza automáticamente cuando los archivos cambian.
        Usa para encontrar símbolos, funciones, módulos o cualquier entidad de código.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Texto a buscar"},
            kind: %{type: "string", description: "function|module|class|struct|interface|type"},
            level: %{type: "string", description: "symbol|chunk|summary (default: chunk)"},
            limit: %{type: "integer", description: "Máximo de resultados (default: 5)"}
          },
          required: ["query"]
        }
      },
      %{
        name: "delfos_symbol",
        description: """
        Devuelve información completa de un símbolo: código fuente, resumen LLM,
        firma, callers, callees y métricas de riesgo. Los datos reflejan el estado
        actual del archivo (re-indexado automáticamente al guardar).
        Usa esto antes de modificar un símbolo.
        """,
        inputSchema: %{
          type: "object",
          properties: %{name: %{type: "string", description: "Nombre parcial o completo"}},
          required: ["name"]
        }
      },
      %{
        name: "delfos_context",
        description: """
        Contexto compacto y denso para una tarea: los símbolos más relevantes
        con código, resúmenes y relaciones. Ideal como primer llamado al empezar.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            task: %{type: "string", description: "Descripción de la tarea"},
            max_symbols: %{type: "integer", description: "Máximo de símbolos (default: 8)"}
          },
          required: ["task"]
        }
      },
      %{
        name: "delfos_callers",
        description: "Qué símbolos llaman al símbolo indicado.",
        inputSchema: %{
          type: "object",
          properties: %{name: %{type: "string", description: "Nombre del símbolo"}},
          required: ["name"]
        }
      },
      %{
        name: "delfos_callees",
        description: "Qué símbolos llama el símbolo indicado.",
        inputSchema: %{
          type: "object",
          properties: %{name: %{type: "string", description: "Nombre del símbolo"}},
          required: ["name"]
        }
      },
      %{
        name: "delfos_impact",
        description:
          "Análisis de impacto BFS: qué símbolos se verían afectados. Usar antes de refactorizar.",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Nombre del símbolo"},
            depth: %{type: "integer", description: "Profundidad BFS (default: 3)"}
          },
          required: ["name"]
        }
      },
      %{
        name: "delfos_audit",
        description:
          "Métricas de deuda técnica: churn, ciclos, instabilidad, TODOs. Sin parámetros = proyecto completo.",
        inputSchema: %{
          type: "object",
          properties: %{
            file: %{type: "string", description: "Ruta relativa (opcional)"}
          }
        }
      },
      %{
        name: "delfos_files",
        description: "Estructura de archivos indexados con lenguaje y métricas básicas.",
        inputSchema: %{
          type: "object",
          properties: %{
            filter: %{type: "string", description: "Filtrar por lenguaje o ruta (opcional)"}
          }
        }
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp elapsed_ms(started_at) do
    max(System.monotonic_time(:millisecond) - started_at, 0)
  end

  defp get_project do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  end

  defp send_response(response) do
    case Jason.encode(response) do
      {:ok, json} -> IO.puts(json)
      {:error, _} -> Logger.error("MCP: failed to encode response")
    end
  end

  defp send_error(id, code, message) do
    case Jason.encode(%{
           jsonrpc: "2.0",
           id: id,
           error: %{code: code, message: message}
         }) do
      {:ok, json} -> IO.puts(json)
      {:error, _} -> :ok
    end
  end

  defp send_notification(method, params) do
    case Jason.encode(%{jsonrpc: "2.0", method: method, params: params}) do
      {:ok, json} -> IO.puts(json)
      {:error, _} -> :ok
    end
  end

  # ── Startup splash (Pulsar) ──────────────────────────────────────────
  # Render a single frame of the pulsar animation showing "Delfos MCP"
  # with a pulsing wave around it, then immediately overwrite with a
  # "ready" frame once the supervision tree is up. The animation is
  # visually distinctive enough to confirm at a glance that the
  # server didn't hang during NIF loading, without polluting stdout
  # (we render to stderr via IO.write).

  defp print_startup_splash do
    if tty?(:stderr) do
      frame =
        Alaja.Components.Pulsar.render_frame(
          "Delfos MCP v#{@server_version}",
          0,
          width: 40,
          height: 5,
          text: "Delfos MCP",
          speed: 80
        )

      IO.write(:stderr, Alaja.Buffer.to_iodata(frame))
    end
  end

  defp print_startup_ready do
    if tty?(:stderr) do
      # Replace the pulsar with a clean "ready" message (same height
      # so it overwrites cleanly via cursor-up sequences).
      ready =
        Alaja.Components.Pulsar.render_frame(
          "ready — listening on stdin",
          0,
          width: 40,
          height: 5,
          text: "READY",
          speed: 200
        )

      IO.write(:stderr, "\e[5A" <> Alaja.Buffer.to_iodata(ready))
      # Pause briefly so the user sees "READY" before messages start.
      Process.sleep(300)
      IO.write(:stderr, "\e[5B\n")
    end
  end

  defp tty?(device) do
    case :io.getopts(device) do
      {:ok, opts} -> Keyword.get(opts, :tty, false)
      _ -> false
    end
  end
end
