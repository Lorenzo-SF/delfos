defmodule Delfos.CLI do
  @moduledoc """
  CLI entry point for Delfos.

  Uses the `Alaja.CLI.Definition` DSL to register all 13 subcommands.
  The thin `main/1` function delegates to the generated dispatcher.

  Each command's logic lives in `Delfos.CLI.Commands.<Name>` and is
  invoked by the handler functions below. Handlers receive the
  DSL-provided opts map directly and forward it to each command's
  `run_with_opts/1` — no argv round-trip (see commit that removed
  the handler-bridge anti-pattern).
  """

  require Logger

  alias Alaja
  alias Delfos.CLI.Commands

  use Alaja.CLI.Definition, otp_app: :delfos

  # ── Handlers ──────────────────────────────────────────────────────────────
  # Each handler receives the DSL opts map (with `_args` key carrying
  # the raw positional args list). They delegate to the existing
  # `Delfos.CLI.Commands.X.run/1` functions.

  @doc false
  def init_handler(%{_args: args, help: help}) do
    if help, do: Commands.Init.run(["--help"]), else: Commands.Init.run(args)
  end

  @doc false
  def scan_handler(%{_args: _args, help: help, full: full, workers: workers}) do
    if help,
      do: Commands.Scan.run(["--help"]),
      else: Commands.Scan.run_with_opts(%{full: full, workers: workers})
  end

  @doc false
  def query_handler(%{_args: args, help: help}) do
    if help, do: Commands.Query.run(["--help"]), else: Commands.Query.run(args)
  end

  @doc false
  def audit_handler(%{_args: _args, help: help, file: file}) do
    if help, do: Commands.Audit.run(["--help"]), else: Commands.Audit.run_with_opts(%{file: file})
  end

  @doc false
  def summarize_handler(%{_args: _args, help: help, level: level, force: force}) do
    if help,
      do: Commands.Summarize.run(["--help"]),
      else: Commands.Summarize.run_with_opts(%{level: level, force: force})
  end

  @doc false
  def explain_handler(%{_args: args, help: help}) do
    if help, do: Commands.Explain.run(["--help"]), else: Commands.Explain.run(args)
  end

  @doc false
  def graph_handler(%{_args: args, help: help, depth: depth}) do
    if help,
      do: Commands.Graph.run(["--help"]),
      else: Commands.Graph.run_with_opts(%{args: args, depth: depth})
  end

  @doc false
  def context_handler(%{_args: _args, help: help, output: output, symbol: symbol}) do
    if help,
      do: Commands.Context.run(["--help"]),
      else: Commands.Context.run_with_opts(%{output: output, symbol: symbol})
  end

  @doc false
  def doctor_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help do
      Commands.Doctor.run(["--help"])
    else
      Commands.Doctor.run_with_opts(%{
        fix: Map.get(attrs, :fix, false),
        json: Map.get(attrs, :json, false),
        interactive: Map.get(attrs, :interactive, false)
      })
    end
  end

  @doc false
  def status_handler(%{_args: args, help: help}) do
    if help, do: Commands.Status.run(["--help"]), else: Commands.Status.run(args)
  end

  @doc false
  def config_handler(%{_args: args, help: help}) do
    if help, do: Commands.Config.run(["--help"]), else: Commands.Config.run(args)
  end

  @doc false
  def integrate_handler(%{_args: args, help: help}) do
    if help, do: Commands.Integrate.run(["--help"]), else: Commands.Integrate.run(args)
  end

  @doc false
  def models_handler(%{_args: args, help: help, probe: _probe}) do
    if help do
      Commands.Models.run(["--help"])
    else
      # Deprecation: redirect to `delfos config models`
      Alaja.print_warning("[deprecated] Use 'delfos config models' instead")
      Commands.Config.run(["models"] ++ args)
    end
  end

  @doc false
  def watch_handler(%{_args: _args}) do
    start_watch()
  end

  @doc false
  def serve_handler(%{_args: _args, mcp: true}) do
    Delfos.MCP.Server.start()
  end

  def serve_handler(%{_args: _args}) do
    Delfos.CLI.Commands.Config.run(["help"])
  end

  @doc false
  def setup_handler(%{_args: args}) do
    # Deprecation: redirect to `delfos config setup`
    Alaja.print_warning("[deprecated] Use 'delfos config setup' instead")
    Commands.Config.run(["setup"] ++ args)
  end

  @doc false
  def version_handler(%{_args: _args}) do
    Alaja.print_info("Delfos v#{Delfos.version()}")
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Watch mode is interactive — it stays alive until Ctrl+C.
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

    # `receive` loop instead of `Process.sleep(:infinity)` so we can
    # handle SIGINT/SIGTERM and stop gracefully. The watcher GenServer
    # (Delfos.Indexer.Watcher) does the actual file watching; the CLI
    # main process just stays alive until signalled.
    watch_loop()
  end

  defp watch_loop do
    receive do
      {:EXIT, _pid, _reason} ->
        # A child process exited — we stay alive; the supervisor
        # will restart it.
        watch_loop()

      {:system, :sigterm} ->
        Logger.info("[delfos] watch — received SIGTERM, shutting down")
        :ok

      {:system, :sigint} ->
        Logger.info("[delfos] watch — received SIGINT, shutting down")
        :ok

      message ->
        Logger.debug("[delfos] watch — unexpected message: #{inspect(message)}")
        watch_loop()
    end
  end

  defp get_active_project do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  rescue
    DBConnection.ConnectionError -> nil
    Ecto.Query.CastError -> nil
  end

  # ── Commands ──────────────────────────────────────────────────────────────

  command "init", "Register project and run first full scan" do
    argument(:path, :string, default: "")
    flag(:help, :boolean, [])
    run({Delfos.CLI, :init_handler})
  end

  command "scan", "Re-scan (incremental by default, --full for everything)" do
    flag(:full, :boolean, [])
    flag(:workers, :integer, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :scan_handler})
  end

  command "query", "Hybrid search (vector + BM25 + graph)" do
    argument(:text, :string, default: "")
    argument(:rest, :string, repeatable: true, default: [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :query_handler})
  end

  command "audit", "Technical debt: hotspots, cycles, instability" do
    flag(:file, :string, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :audit_handler})
  end

  command "summarize", "Generate LLM summaries" do
    flag(:level, :integer, [])
    flag(:force, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :summarize_handler})
  end

  command "explain", "LLM explanation of a symbol" do
    argument(:name, :string, default: "")
    argument(:rest, :string, repeatable: true, default: [])
    flag(:fresh, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :explain_handler})
  end

  command "graph", "Graph queries: callers/callees/impact/cycles" do
    argument(:subcommand, :string, default: "")
    argument(:name, :string, default: "")
    argument(:rest, :string, repeatable: true, default: [])
    flag(:depth, :integer, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :graph_handler})
  end

  command "context", "AGENTS.md + CLAUDE.md for the project" do
    flag(:output, :string, [])
    flag(:symbol, :string, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :context_handler})
  end

  command "config", "Manage Delfos configuration (LLM, providers, models)" do
    argument(:action, :string, default: "")
    argument(:key, :string, default: "")
    argument(:value, :string, default: "")
    flag(:show, :boolean, short: :s)
    flag(:help, :boolean, [])
    run({Delfos.CLI, :config_handler})
  end

  command "integrate", "Configure MCP integration with AI agents" do
    argument(:agent, :string, default: "all")
    argument(:rest, :string, repeatable: true, default: [])
    flag(:yes, :boolean, [])
    flag(:project, :string, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :integrate_handler})
  end

  command "doctor", "Check PostgreSQL, pgvector, tree-sitter and config file" do
    flag(:fix, :boolean, [])
    flag(:json, :boolean, [])
    flag(:interactive, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :doctor_handler})
  end

  command "models", "Show active embedding/LLM models" do
    flag(:probe, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :models_handler})
  end

  command "status", "Index status and registered projects" do
    flag(:help, :boolean, [])
    run({Delfos.CLI, :status_handler})
  end

  command "watch", "File watcher + auto re-indexing" do
    run({Delfos.CLI, :watch_handler})
  end

  command "serve", "MCP stdio server (with real-time indexing)" do
    flag(:mcp, :boolean, [])
    run({Delfos.CLI, :serve_handler})
  end

  command "version", "Show installed Delfos version" do
    run({Delfos.CLI, :version_handler})
  end

  command "setup", "Interactive setup wizard (DB, models, config)" do
    run({Delfos.CLI, :setup_handler})
  end
end
