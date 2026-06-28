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

  Indexado en tiempo real:
    El Watcher re-indexa archivos modificados en background.
    Al completar un lote de re-indexado, IndexBroadcaster envía
    notifications/tools/list_changed a este proceso, que lo reenvía
    al cliente MCP por stdout.

  Arrancar:
    delfos serve --mcp
  """

  require Logger

  alias Delfos.MCP.{Tools, IndexBroadcaster}

  @protocol_version "2024-11-05"
  @server_name "delfos"
  @server_version Delfos.version()

  def start do
    # Configurar modo MCP antes de arrancar la app
    Application.put_env(:delfos, :mode, :mcp)
    Application.ensure_all_started(:delfos)

    # Registrar este proceso para recibir notificaciones de cambio de índice
    IndexBroadcaster.register_client(self())

    # Lanzar proceso separado que lee stdin (bloqueante) y envía mensajes
    # al loop principal. Esto evita que IO.gets bloquee el receive loop
    # y permite procesar notificaciones en tiempo real.
    _stdin_pid = spawn_link(fn -> stdin_reader() end)

    IO.puts(:standard_error, "[INFO] Delfos MCP v#{@server_version} iniciado")
    loop(%{initialized: false})
  end

  # ---------------------------------------------------------------------------
  # Lector de stdin en proceso separado
  # ---------------------------------------------------------------------------

  defp stdin_reader do
    case IO.gets("") do
      :eof ->
        send(Process.whereis(Delfos.MCP.Server) || self(), {:stdin, :eof})

      {:error, reason} ->
        send(Process.whereis(Delfos.MCP.Server) || self(), {:stdin, {:error, reason}})

      line ->
        send(Process.whereis(Delfos.MCP.Server) || self(), {:stdin, String.trim(line)})
        stdin_reader()
    end
  end

  # ---------------------------------------------------------------------------
  # Loop principal stdio
  # ---------------------------------------------------------------------------

  defp loop(state) do
    receive do
      # Notificación del IndexBroadcaster: el índice cambió
      {:mcp_notification, json} ->
        if state.initialized do
          IO.puts(json)
        end

        loop(state)

      {:stdin, line_or_eof} ->
        handle_stdin(line_or_eof, state)
    end
  end

  defp handle_stdin(:eof, _state) do
    IO.puts(:standard_error, "[INFO] MCP: EOF, cerrando")
    :ok
  end

  defp handle_stdin({:error, reason}, _state) do
    IO.puts(:standard_error, "[ERROR] MCP stdin: #{inspect(reason)}")
    :ok
  end

  defp handle_stdin("", state), do: loop(state)

  defp handle_stdin(line, state) do
    case Jason.decode(line) do
      {:ok, msg} ->
        {response, new_state} = handle_message(msg, state)
        if response, do: send_response(response)
        loop(new_state)

      {:error, _} ->
        send_error(nil, -32700, "Parse error")
        loop(state)
    end
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
          # Declarar soporte para notificaciones de cambio
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

  defp handle_message(%{"method" => "tools/call", "id" => id, "params" => params}, state) do
    tool_name = params["name"]
    arguments = params["arguments"] || %{}
    project = get_project()

    result =
      case tool_name do
        "delfos_search" -> Tools.search(project, arguments)
        "delfos_symbol" -> Tools.symbol(project, arguments)
        "delfos_context" -> Tools.context(project, arguments)
        "delfos_callers" -> Tools.callers(project, arguments)
        "delfos_callees" -> Tools.callees(project, arguments)
        "delfos_impact" -> Tools.impact(project, arguments)
        "delfos_audit" -> Tools.audit(project, arguments)
        "delfos_files" -> Tools.files(project, arguments)
        _ -> {:error, "Herramienta desconocida: #{tool_name}"}
      end

    response =
      case result do
        {:ok, content} ->
          %{jsonrpc: "2.0", id: id, result: %{content: [%{type: "text", text: content}]}}

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

    {response, state}
  end

  defp handle_message(%{"id" => id}, state) do
    {%{jsonrpc: "2.0", id: id, error: %{code: -32601, message: "Method not found"}}, state}
  end

  defp handle_message(_, state), do: {nil, state}

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

  defp get_project do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  end

  defp send_response(response) do
    case Jason.encode(response) do
      {:ok, json} -> IO.puts(json)
      {:error, _} -> IO.puts(:standard_error, "[ERROR] MCP: failed to encode response")
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
end
