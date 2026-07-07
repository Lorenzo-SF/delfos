defmodule Delfos.CLI.Commands.MCP do
  @moduledoc """
  MCP stdio server (with real-time indexing).

  Starts the Delfos MCP server on stdio, enabling AI agents to query
  Delfos for code intelligence (search, impact analysis, context, audit).

  This is the only serve mode currently available. The command starts the
  server and blocks until the MCP client closes the connection (Ctrl+C
  from a terminal, EOF from stdin, or agent exit).
  """

  alias Alaja

  @help """
  USAGE
      delfos mcp

  Start the Delfos MCP stdio server.

  The server reads JSON-RPC requests from stdin and writes responses to
  stdout. It is designed to be launched by an AI agent as a subprocess;
  for testing you can pipe messages in manually.

  EXAMPLES
      # From an AI agent (Cursor, Claude, Zed, etc.) — agent launches this
      # command as a subprocess and communicates via stdio.
      delfos mcp

      # Endpoints exposed:
      #   search        Hybrid search (vector + BM25 + graph)
      #   lookup        Symbol lookup by name
      #   context       Task-relevant symbol context
      #   callers       Incoming call graph
      #   callees       Outgoing call graph
      #   impact        Transitive impact analysis
      #   audit         Technical debt hotspots
      #   structure     Indexed file structure

  For integration recipes see 'delfos integrate --help' or the docs.
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(_args) do
    Delfos.MCP.Server.start()
  end
end
