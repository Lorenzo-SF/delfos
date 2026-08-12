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
  alias Delfos.CLI.LLMGuard

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
  def agents_handler(%{_args: _args, help: help, output: output, symbol: symbol}) do
    if help,
      do: Commands.Agents.run(["--help"]),
      else: Commands.Agents.run_with_opts(%{output: output, symbol: symbol})
  end

  @doc false
  def context_handler(%{_args: _args, help: help, output: output, symbol: symbol}) do
    # Deprecated alias of `delfos agents`. Forward after a one-line
    # warning so old muscle memory still works.
    unless help do
      Alaja.print_warning(
        "'delfos context' is deprecated and will be removed in a future release. " <>
          "Use 'delfos agents' instead (same flags)."
      )
    end

    if help,
      do: Commands.Agents.run(["--help"]),
      else: Commands.Agents.run_with_opts(%{output: output, symbol: symbol})
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
  def models_handler(_attrs) do
    Alaja.print_error(
      "'delfos models' has been merged into 'delfos config'. Use:\n  delfos config models"
    )

    System.halt(1)
  end

  @doc false
  def watch_handler(%{_args: _args}) do
    Alaja.print_warning(
      "'delfos watch' has been merged into 'delfos mcp'. The MCP server " <>
        "now includes the file watcher, so you don't need to run a separate " <>
        "'delfos watch' process. Forwarding to 'delfos mcp' — Ctrl+C to stop."
    )

    Delfos.MCP.Server.start()
  end

  @doc false
  def mcp_handler(%{_args: _args}) do
    Delfos.MCP.Server.start()
  end

  @doc false
  def setup_handler(_attrs) do
    Alaja.print_error(
      "'delfos setup' has been merged into 'delfos config'. Use:\n  delfos config setup"
    )

    System.halt(1)
  end

  @doc false
  def version_handler(%{_args: _args} = attrs) do
    # Bug #11 fix: 'delfos version --help' ahora muestra ayuda en vez
    # de ignorar el flag. Antes el --help se descartaba y se
    # ejecutaba el handler de version, dando el mismo output que
    # 'delfos version' puro.
    if Map.get(attrs, :help, false) do
      Alaja.print_raw("""
      Usage: delfos version [flags]

      Show the installed Delfos version.

      Flags:
        --help, -h     Show this help
      """)
    else
      Alaja.print_info("Delfos v#{Delfos.version()}")
    end
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

  command "agents", "AGENTS.md + CLAUDE.md for the project" do
    flag(:output, :string, [])
    flag(:symbol, :string, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :agents_handler})
  end

  # Deprecated alias of `agents`. Kept so that older scripts and docs
  # that say `delfos context` still work, but the user gets a clear
  # message that the name changed.
  command "context", "(deprecated) use 'delfos agents' instead" do
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

  command "status", "Index status and registered projects" do
    flag(:help, :boolean, [])
    run({Delfos.CLI, :status_handler})
  end

  command "watch", "[deprecated] forwards to 'delfos mcp'" do
    run({Delfos.CLI, :watch_handler})
  end

  command "mcp", "Start MCP stdio server (used by AI agents to query Delfos)" do
    run({Delfos.CLI, :mcp_handler})
  end

  command "version", "Show installed Delfos version" do
    flag(:help, :boolean, [])
    run({Delfos.CLI, :version_handler})
  end

  # ── Global flags ──────────────────────────────────────────────────────────
  # Override main/1 to intercept --help/--version before the dispatcher.
  # dispatch_main/1 is generated by Alaja.CLI.Definition.

  @doc false
  def main(["--help" | _rest]) do
    show_general_help()
  end

  def main(["-h" | _rest]) do
    show_general_help()
  end

  def main(["--version" | _rest]) do
    Alaja.print_info("Delfos v#{Delfos.version()}")
  end

  def main(["-v" | _rest]) do
    Alaja.print_info("Delfos v#{Delfos.version()}")
  end

  def main([]) do
    # Bug #10 fix: 'delfos' (sin args) ahora muestra el help
    # estilizado de Alaja, igual que 'delfos --help'. Antes mostraba
    # "Error: no command specified" en texto plano, inconsistente con
    # --help que usa la tabla Alaja. exit 0 (no es un error pedir
    # ayuda).
    show_general_help()
  end

  def main(args) do
    # CRITICAL: `delfos eval` uses `start_clean.boot` which does NOT
    # start OTP applications. We must start the app chain here before
    # any LLM guard probes or command dispatch. This is a no-op if the
    # apps were already started by a full boot script.
    #
    # We start :logger first to ensure the I/O server (and especially
    # :standard_error) is initialized before any other app boots. This
    # prevents boot-time crashes where a dying process tries to log an
    # error to :standard_error before the device exists.
    Application.ensure_all_started(:logger)
    Application.ensure_all_started(:delfos)

    # Ensure the Ecto Repo is running before dispatching any command.
    # Many CLI commands (`status`, `query`, `scan`, `audit`, `context`,
    # `graph`, `explain`, `summarize`, `init`, etc.) call
    # `Delfos.Repo.one/all/...` directly without first calling
    # `RepoStarter.start_repo/0`. Starting it here ensures the Repo
    # registry is populated by the time any command runs.
    #
    # `start_repo/0` is idempotent and bounded by ~10s; commands that
    # don't need the DB won't be affected since they never touch it.
    case Delfos.RepoStarter.start_repo() do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        # Don't abort here — commands that don't need DB will work fine.
        # Commands that do need DB will surface a clearer error when they
        # try to query.
        Logger.debug("[delfos] Repo not started at boot: #{inspect(reason)}")
    end

    check_llm_guard(args)
    result = dispatch_main(args)

    # Bug #5 fix: antes, dispatch_main devolvía {:error, :unknown_command}
    # o {:error, :handler} desde Alaja.ErrorHandler, pero esos tuples
    # no provocaban System.halt → exit 0. Ahora halt con código 1
    # en cualquier error del dispatcher. exit 78 se reserva para
    # LLMGuard (ya manejado por check_llm_guard).
    case result do
      {:error, _} -> System.halt(1)
      _ -> :ok
    end
  end

  # Pre-flight LLM availability check. Looks at the first positional
  # argument (the command name) and asks the LLMGuard whether the
  # configured endpoints can support it.
  #
  # Behaviour:
  #   :ok              → continue (either LLM is reachable or not needed)
  #   :warn            → already printed a warning; continue
  #   {:halt, reason}  → already printed an error; System.halt(78)
  defp check_llm_guard([first | rest]) do
    # Skip the guard when the user is just asking for help or showing
    # the version — these are read-only operations that don't actually
    # need a running LLM.
    if "--help" in rest or "-h" in rest do
      :ok
    else
      case LLMGuard.check(first) do
        :ok -> :ok
        :warn -> :ok
        {:halt, _} -> System.halt(78)
      end
    end
  end

  defp check_llm_guard(_args), do: :ok

  defp show_general_help do
    Alaja.Components.Header.print("Delfos",
      subtitle: "Code Intelligence & Context Server",
      size: :medium
    )

    Alaja.print_raw("")

    commands = __commands__()

    rows =
      Enum.map(commands, fn cmd ->
        [cmd.name, cmd.description]
      end)

    Alaja.Components.Table.print(
      headers: ["Command", "Description"],
      rows: rows,
      table_border: :rounded,
      headers_color: :cyan,
      headers_effects: [:bold]
    )

    Alaja.print_raw("")

    Alaja.print_raw("  GLOBAL FLAGS")
    Alaja.print_raw("    --help, -h       Show this help")
    Alaja.print_raw("    --version, -v    Show installed version")
    Alaja.print_raw("")
  end
end
