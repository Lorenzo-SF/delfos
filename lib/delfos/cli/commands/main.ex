defmodule Delfos.CLI.Main do
  @moduledoc """
  CLI entry point for Delfos. Dispatches to `Delfos.CLI.Commands.*`.

  All user-facing output goes through `Alaja` (icons, colours) so the
  CLI stays consistent with the rest of the Lorenzo-SF OSS ecosystem.
  """

  alias Alaja
  alias Delfos.CLI.Commands

  def main(args) do
    Application.ensure_all_started(:delfos)

    case args do
      ["init" | rest] ->
        Commands.Init.run(rest)

      ["scan" | rest] ->
        Commands.Scan.run(rest)

      ["query" | rest] ->
        Commands.Query.run(rest)

      ["audit" | rest] ->
        Commands.Audit.run(rest)

      ["summarize" | rest] ->
        Commands.Summarize.run(rest)

      ["explain" | rest] ->
        Commands.Explain.run(rest)

      ["graph" | rest] ->
        Commands.Graph.run(rest)

      ["context" | rest] ->
        Commands.Context.run(rest)

      ["doctor" | rest] ->
        Commands.Doctor.run(rest)

      ["status" | rest] ->
        Commands.Status.run(rest)

      ["config" | rest] ->
        Commands.Config.run(rest)

      ["integrate" | rest] ->
        Commands.Integrate.run(rest)

      ["watch" | _] ->
        start_watch()

      ["serve", "--mcp"] ->
        Delfos.MCP.Server.start()

      ["version" | _] ->
        Alaja.print_info("Delfos v#{Delfos.version()}")

      ["help" | _] ->
        print_help()

      [] ->
        print_help()

      [cmd | _] ->
        Alaja.print_error("Unknown command: #{cmd}")
        Alaja.print_raw("\n")
        print_help()
    end
  end

  # ---------------------------------------------------------------------------
  # Watch mode
  # ---------------------------------------------------------------------------

  defp start_watch do
    Application.put_env(:delfos, :watch, true)

    project = get_active_project()

    unless project do
      Alaja.print_error("No projects registered. Run: delfos init .")
      System.halt(1)
    end

    Alaja.print_info("Watching: #{project.path}")
    Alaja.print_info("Re-indexing changes automatically. Ctrl+C to exit.")
    Alaja.print_raw("\n")

    # The Watcher already started in application.ex because watch: true.
    # We only need to keep the process alive.
    Process.sleep(:infinity)
  end

  defp get_active_project do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  rescue
    _ -> nil
  end

  # ---------------------------------------------------------------------------
  # Help
  # ---------------------------------------------------------------------------

  defp print_help do
    Alaja.print_raw("""

    Delfos v#{Delfos.version()} — Semantic knowledge base for software projects

    USAGE
      delfos <command> [options]

    INITIALIZATION
      init [path]             Register project and run first full scan
      scan                    Re-scan (incremental by default)
                              --full to re-index everything  --workers N (default: 4)

    SEARCH & QUERY
      query <text>            Hybrid search (vector + BM25 + graph)
                              --kind function|module|class|struct|interface
                              --level summary|symbol|chunk
                              -n <N>   --format json
      explain <name>          LLM explanation of a symbol (--fresh to regenerate)

    ANALYSIS
      audit                   Technical debt: hotspots, cycles, instability
                              --file <path> for single-file analysis
      summarize               Generate LLM summaries  --level 3|4  --force

    GRAPH
      graph callers <name>    Who calls this symbol  --depth N
      graph callees <name>    What this symbol calls  --depth N
      graph impact  <name>    Impact of changing it  --depth N (default 3)
      graph cycles            Files in dependency cycles

    CONTEXT FOR AGENTS
      context                 AGENTS.md + CLAUDE.md for the project
                              --output <dir>  --symbol <name>

    CONFIGURATION
      config show             Active configuration
      config init             Create ~/.config/delfos/delfos.conf
      config set <s> <k> <v>  Edit a value
      config get <s> <k>      Read a value
      config preset <name>    local | anthropic | openai | openai-large

    AI AGENT INTEGRATION
      integrate [agent]       Configure MCP integration
                              claude-code | opencode | cursor | aider | codex | zed | all
                              --yes to skip prompts
      serve --mcp             MCP stdio server (with real-time indexing)
      watch                   File watcher + auto re-indexing (CLI mode)

    DIAGNOSTICS
      doctor [--fix]          Check DB, pgvector, servers, NIF, coverage
      status                  Index status and registered projects
      version                 Installed version

    EXAMPLES
      delfos init .
      delfos config preset local
      delfos integrate all --yes
      delfos serve --mcp
      delfos query "JWT authentication"
      delfos graph impact PaymentService --depth 5
      delfos explain UserController.create --fresh
      delfos audit --file lib/payments.ex
    """)
  end
end
