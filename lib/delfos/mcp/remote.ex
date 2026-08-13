defmodule Delfos.MCP.Remote.Router do
  @moduledoc """
  HTTP/SSE transport for the MCP server (Plug.Router).

  FE-7: enables remote access to the same tools exposed via stdio.
  Two endpoints:
    GET  /sse       — opens a Server-Sent Events stream. Clients
                       listen here for server-pushed notifications.
    POST /messages  — sends a JSON-RPC request. Response is sent
                       back as a single SSE event on the open stream.

  This is an MVP — only the basics (initialize, tools/list,
  tools/call) are wired up. SSE notifications (tools/list_changed)
  are pushed via IndexBroadcaster.

  SECURITY: no auth by default. Production deployments should
  sit behind a reverse proxy (TLS + auth) or use the new
  auth_token feature (S1).
  """

  use Plug.Router

  alias Plug.Conn

  @max_body_bytes 1_000_000

  plug :match
  plug :dispatch

  get "/" do
    Conn.send_resp(conn, 200, "Delfos MCP HTTP/SSE — use GET /sse, POST /messages")
  end

  get "/sse" do
    handle_sse(conn)
  end

  post "/messages" do
    handle_post(conn)
  end

  match _ do
    Conn.send_resp(conn, 404, "Not found")
  end

  defp handle_sse(conn) do
    conn_id = "delfos-#{System.unique_integer([:positive])}"

    conn =
      conn
      |> Conn.put_resp_header("content-type", "text/event-stream")
      |> Conn.put_resp_header("cache-control", "no-cache")
      |> Conn.put_resp_header("connection", "keep-alive")
      |> Conn.put_resp_header("x-accel-buffering", "no")
      |> Conn.send_chunked(200)
      |> Conn.chunk(
        "event: endpoint\ndata: /messages?session_id=#{conn_id}\n\n"
      )

    Delfos.MCP.IndexBroadcaster.register_client(self())

    Process.send_after(self(), :sse_heartbeat, 15_000)

    sse_loop(conn, conn_id)
  end

  defp sse_loop(conn, conn_id) do
    receive do
      :sse_heartbeat ->
        {:ok, _conn} = Conn.chunk(conn, ":heartbeat\n\n")
        Process.send_after(self(), :sse_heartbeat, 15_000)
        sse_loop(conn, conn_id)

      {:notification, payload} ->
        {:ok, _conn} =
          Conn.chunk(
            conn,
            "event: notification\ndata: #{Jason.encode!(payload)}\n\n"
          )

        sse_loop(conn, conn_id)

      {:stop_sse, _reason} ->
        :ok
    end
  end

  defp handle_post(conn) do
    {:ok, body, conn} = Conn.read_body(conn, length: @max_body_bytes)

    response =
      case Jason.decode(body) do
        {:ok, request} ->
          try do
            # Process through the SAME loop as stdio. The actual
            # server logic lives in Delfos.MCP.Server — we just
            # convert the HTTP request to a stdio-shaped message and
            # extract the response.
            {:reply, payload, _new_state} = Delfos.MCP.Server.handle_request(request)

            case payload do
              list when is_list(list) -> %{"results" => list}
              other -> other
            end
          rescue
            e -> %{"error" => "Server error: #{Exception.message(e)}"}
          end

        {:error, _} ->
          %{"error" => "Invalid JSON"}
      end

    conn
    |> Conn.put_resp_content_type("application/json")
    |> Conn.send_resp(200, Jason.encode!(response))
  end
end

defmodule Delfos.MCP.Remote do
  @moduledoc """
  Entry point for the HTTP/SSE MCP server.
  """
  require Logger

  @doc """
  Starts the HTTP/SSE MCP server on the given port. Defaults to 8080.
  Returns `{:ok, pid}` for the supervisor.
  """
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts \\ []) do
    port = Keyword.get(opts, :port, 8080)

    case Bandit.start_link(plug: Delfos.MCP.Remote.Router, port: port) do
      {:ok, pid} ->
        Logger.info("MCP HTTP/SSE server listening on http://localhost:#{port}")
        {:ok, pid}

      err ->
        err
    end
  end

  @doc """
  Returns the Plug.Router module that handles the RPC endpoints.
  Used by tests and by `start/1`.
  """
  @spec router() :: module()
  def router, do: Delfos.MCP.Remote.Router
end
