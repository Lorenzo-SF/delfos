defmodule Delfos.CLI do
  @moduledoc """
  CLI entry point for Delfos.

  Uses the `Alaja.CLI.Definition` DSL to register all 13 subcommands.
  The thin `main/1` function delegates to the generated dispatcher.

  Each command's logic lives in `Delfos.CLI.Commands.<Name>` and is
  invoked by the handler functions below. The handler functions
  convert the DSL-provided `opts` map (with flag values + raw `_args`)
  into the legacy `run/1` call signature so the existing command
  implementations don't need to change.
  """

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
    args = build_args([{"--full", full}, {"--workers", workers}])
    if help, do: Commands.Scan.run(["--help"]), else: Commands.Scan.run(args)
  end

  @doc false
  def query_handler(%{_args: args, help: help}) do
    if help, do: Commands.Query.run(["--help"]), else: Commands.Query.run(args)
  end

  @doc false
  def audit_handler(%{_args: _args, help: help, file: file}) do
    args = build_args([{"--file", file}])
    if help, do: Commands.Audit.run(["--help"]), else: Commands.Audit.run(args)
  end

  @doc false
  def summarize_handler(%{_args: _args, help: help, level: level, force: force}) do
    args = build_args([{"--level", level}, {"--force", force}])
    if help, do: Commands.Summarize.run(["--help"]), else: Commands.Summarize.run(args)
  end

  @doc false
  def explain_handler(%{_args: args, help: help}) do
    if help, do: Commands.Explain.run(["--help"]), else: Commands.Explain.run(args)
  end

  @doc false
  def graph_handler(%{_args: args, help: help, depth: depth}) do
    args = args ++ build_args([{"--depth", depth}])
    if help, do: Commands.Graph.run(["--help"]), else: Commands.Graph.run(args)
  end

  @doc false
  def context_handler(%{_args: _args, help: help, output: output, symbol: symbol}) do
    args = build_args([{"--output", output}, {"--symbol", symbol}])
    if help, do: Commands.Context.run(["--help"]), else: Commands.Context.run(args)
  end

  @doc false
  def doctor_handler(attrs) do
    help = Map.get(attrs, :help, false)
    fix = Map.get(attrs, :fix, false)
    json = Map.get(attrs, :json, false)
    interactive = Map.get(attrs, :interactive, false)
    db_only = Map.get(attrs, :db_only, false)
    llm_only = Map.get(attrs, :llm_only, false)

    args =
      build_args([
        {"--fix", fix},
        {"--json", json},
        {"--interactive", interactive},
        {"--db-only", db_only},
        {"--llm-only", llm_only}
      ])

    if help, do: Commands.Doctor.run(["--help"]), else: Commands.Doctor.run(args)
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
  def models_handler(%{_args: _args, help: help, probe: probe}) do
    args = build_args([{"--probe", probe}])
    if help, do: Commands.Models.run(["--help"]), else: Commands.Models.run(args)
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
  def version_handler(%{_args: _args}) do
    Alaja.print_info("Delfos v#{Delfos.version()}")
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Convert a list of {flag, value} into the legacy argv string list.
  # Boolean true -> just the flag. Nil values are skipped. Everything
  # else becomes ["--flag", "value"].
  defp build_args(pairs) do
    Enum.flat_map(pairs, fn
      {flag, true} -> [flag]
      {flag, value} when is_binary(value) and value != "" -> [flag, value]
      {flag, value} when is_integer(value) -> [flag, Integer.to_string(value)]
      {_flag, _} -> []
    end)
  end

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

    Process.sleep(:infinity)
  end

  defp get_active_project do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  rescue
    _ -> nil
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

  command "config", "Manage Delfos configuration" do
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

  command "doctor", "Check DB, pgvector, servers, NIF, coverage" do
    flag(:fix, :boolean, [])
    flag(:json, :boolean, [])
    flag(:interactive, :boolean, [])
    flag(:db_only, :boolean, [])
    flag(:llm_only, :boolean, [])
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
end
