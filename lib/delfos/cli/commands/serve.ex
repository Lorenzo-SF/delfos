defmodule Delfos.CLI.Commands.Serve do
  @moduledoc """
  MCP stdio server (with real-time indexing).

  Starts the MCP server on stdio, enabling AI agents to query Delfos
  for code intelligence (search, impact analysis, context, audit).
  """

  alias Alaja

  @help """
  USAGE
      delfos serve [--mcp]

  Start the Delfos MCP stdio server.

  FLAGS
      --mcp     Run in MCP stdio mode (default: enabled, the flag is
                provided for forward compatibility with future serve
                modes)

  EXAMPLES
      delfos serve           # Start MCP server on stdio
      delfos serve --mcp     # Same (explicit)

  The MCP server exposes the following tools:
    - search        Hybrid search (vector + BM25 + graph)
    - lookup        Symbol lookup by name
    - context       Task-relevant symbol context
    - callers       Incoming call graph
    - callees       Outgoing call graph
    - impact        Transitive impact analysis
    - audit         Technical debt hotspots
    - structure     Indexed file structure
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    # When --mcp is absent, opts will have mcp: true as default
    # from the DSL flag definition.
    mcp? = Enum.member?(args, "--mcp") or Enum.member?(args, "-m")
    if mcp? or args == [] do
      Delfos.MCP.Server.start()
    else
      Delfos.MCP.Server.start()
    end
  end
end
