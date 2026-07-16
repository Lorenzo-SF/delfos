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
  # Each handler receives the DSL opts map directly (no argv round-trip).
  # They pull flags/args from the map and call `Commands.X.run_with_opts/1`.
  # Help is rendered via the module's `help_text/0` (uniform across the CLI).

  @doc false
  def init_handler(attrs) do
    help = Map.get(attrs, :help, false)
    path = Map.get(attrs, :path, "")

    if help,
      do: Alaja.print_raw(Commands.Init.help_text()),
      else: Commands.Init.run_with_opts(%{path: path})
  end

  @doc false
  def scan_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help do
      Alaja.print_raw(Commands.Scan.help_text())
    else
      Commands.Scan.run_with_opts(%{
        full: Map.get(attrs, :full, false),
        workers: Map.get(attrs, :workers, nil)
      })
    end
  end

  @doc false
  def query_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help do
      Alaja.print_raw(Commands.Query.help_text())
    else
      text = Map.get(attrs, :text, "")
      rest = Map.get(attrs, :rest, [])

      Commands.Query.run_with_opts(%{
        kind: Map.get(attrs, :kind, nil),
        level: Map.get(attrs, :level, nil),
        n: Map.get(attrs, :n, nil),
        format: Map.get(attrs, :format, nil),
        rest: [text | rest] |> Enum.reject(&(&1 in [nil, ""]))
      })
    end
  end

  @doc false
  def audit_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help,
      do: Alaja.print_raw(Commands.Audit.help_text()),
      else:
        Commands.Audit.run_with_opts(%{
          file: Map.get(attrs, :file, nil),
          with_explanation: Map.get(attrs, :with_explanation, false),
          llm_less: Map.get(attrs, :llm_less, false)
        })
  end

  @doc false
  def summarize_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help,
      do: Alaja.print_raw(Commands.Summarize.help_text()),
      else:
        Commands.Summarize.run_with_opts(%{
          level: Map.get(attrs, :level, 3),
          force: Map.get(attrs, :force, false)
        })
  end

  @doc false
  def explain_handler(attrs) do
    cond do
      Map.get(attrs, :help, false) ->
        Alaja.print_raw(Commands.Explain.help_text())

      Map.get(attrs, :name, "") == nil or Map.get(attrs, :name, "") == "" ->
        Alaja.print_error("Usage: delfos explain <name>")
        System.halt(1)

      true ->
        Commands.Explain.run_with_opts(%{
          name: Map.get(attrs, :name, ""),
          fresh: Map.get(attrs, :fresh, false)
        })
    end
  end

  @doc false
  def graph_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help,
      do: Alaja.print_raw(Commands.Graph.help_text()),
      else:
        Commands.Graph.run_with_opts(%{
          args:
            [Map.get(attrs, :subcommand, ""), Map.get(attrs, :name, "")]
            |> Enum.reject(&(&1 in [nil, ""])),
          depth: Map.get(attrs, :depth, nil)
        })
  end

  @doc false
  def agents_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help,
      do: Alaja.print_raw(Commands.Agents.help_text()),
      else:
        Commands.Agents.run_with_opts(%{
          output: Map.get(attrs, :output, nil),
          with_explanation: Map.get(attrs, :with_explanation, false),
          llm_less: Map.get(attrs, :llm_less, false)
        })
  end

  @doc false
  def doctor_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help,
      do: Alaja.print_raw(Commands.Doctor.help_text()),
      else:
        Commands.Doctor.run_with_opts(%{
          fix: Map.get(attrs, :fix, false),
          json: Map.get(attrs, :json, false),
          guided: Map.get(attrs, :guided, false)
        })
  end

  @doc false
  def status_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help,
      do: Alaja.print_raw(Commands.Status.help_text()),
      else: Commands.Status.run_with_opts(%{stats: Map.get(attrs, :stats, false)})
  end

  @doc false
  def config_handler(attrs) do
    help = Map.get(attrs, :help, false)

    # Config takes positional subcommand args; fall back to the legacy
    # run/1 path until B5 finishes the config subcommand refactor.
    args = Map.get(attrs, :_args, [])

    if help, do: Commands.Config.run(["--help"]), else: Commands.Config.run(args)
  end

  @doc false
  def integrate_handler(attrs) do
    help = Map.get(attrs, :help, false)

    if help,
      do: Commands.Integrate.run(["--help"]),
      else:
        Commands.Integrate.run(
          [Map.get(attrs, :agent, "all") | Map.get(attrs, :rest, [])] ++
            if(Map.get(attrs, :yes, false), do: ["--yes"], else: []) ++
            case Map.get(attrs, :project) do
              nil -> []
              p -> ["--project", p]
            end
        )
  end

  @doc false
  def mcp_handler(%{_args: _args}) do
    Delfos.MCP.Server.start()
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
        --json         Machine-readable version info
        --no-splash    Skip the Pulsar animation
      """)
    else
      if Map.get(attrs, :json, false) do
        Alaja.print_raw(build_version_json())
      else
        print_version_with_splash(Map.get(attrs, :no_splash, false) == true)
      end
    end
  end

  # UX13: 'delfos version' now renders a Pulsar splash (when stderr is
  # a TTY and --no-splash isn't set) followed by a build-info block
  # with: elixir/otp versions, git branch + commit, NIF status.
  defp print_version_with_splash(no_splash?) do
    if not no_splash? and tty?(:stderr) do
      frame =
        Alaja.Components.Pulsar.render_frame(
          "Delfos v#{Delfos.version()}",
          0,
          width: 40,
          height: 5,
          text: "Delfos",
          speed: 100
        )

      IO.write(:stderr, Alaja.Buffer.to_iodata(frame))
      # tiny pause so the splash is actually visible (default 60ms frame)
      Process.sleep(120)
      IO.write(:stderr, "\e[5A\r\e[J")
    end

    Alaja.Components.Box.print(build_version_block(),
      title: "Delfos v#{Delfos.version()}",
      border: :rounded,
      border_color: {0, 180, 216},
      padding: 1
    )
  end

  defp build_version_block do
    elixir_vsn = System.version()
    otp_vsn = System.otp_release() |> to_string()
    branch = git_branch() || "—"
    commit = git_commit() || "—"

    """
      Elixir:        #{elixir_vsn}
      OTP:           #{otp_vsn}
      Git:           #{branch} @ #{commit}
      NIF (tree-sitter): #{nif_status()}
      Compiled at:   #{compile_timestamp()}
    """
  end

  defp build_version_json do
    %{
      version: Delfos.version(),
      elixir: System.version(),
      otp: System.otp_release() |> to_string(),
      git_branch: git_branch(),
      git_commit: git_commit(),
      nif_loaded: nif_loaded?(),
      compiled_at: compile_timestamp()
    }
    |> Jason.encode!(pretty: true)
  end

  defp git_branch do
    case System.cmd("git", ["-C", File.cwd!(), "rev-parse", "--abbrev-ref", "HEAD"],
           stderr_to_stdout: true
         ) do
      {out, 0} -> out |> String.trim()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp git_commit do
    case System.cmd("git", ["-C", File.cwd!(), "rev-parse", "--short", "HEAD"],
           stderr_to_stdout: true
         ) do
      {out, 0} -> out |> String.trim()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Returns "loaded" or "NOT LOADED (parsers will fall back to regex)".
  # We probe via Code.ensure_loaded?/1 since that's how Alaja and other
  # libs do it; if the NIF is compiled but its load callback throws,
  # the loaded? check returns false and we report the failure.
  defp nif_status do
    if nif_loaded?(), do: "loaded", else: "NOT LOADED (regex fallback active)"
  end

  defp nif_loaded? do
    case Application.ensure_all_started(:delfos) do
      {:ok, _} ->
        Code.ensure_loaded?(:tree_sitter) and
          not is_nil(Process.whereis(TreeSitter.NIF))

      _ ->
        false
    end
  rescue
    _ -> false
  end

  # The compile timestamp is captured at module-compile time as a
  # module attribute. Not perfect (won't update on rebuild of a
  # single module) but good enough for the splash.
  @compile_timestamp DateTime.utc_now() |> DateTime.to_iso8601()

  defp compile_timestamp, do: @compile_timestamp

  # When stderr is captured by ExUnit.CaptureIO, :io.getopts raises
  # `ArgumentError`. Treat as non-tty so we don't try to animate /
  # write escape codes into a captured stream.
  defp tty?(:stderr) do
    try do
      case :io.getopts(:standard_error) do
        {:ok, opts} -> Keyword.get(opts, :tty, false)
        _ -> false
      end
    rescue
      ArgumentError -> false
      _ -> false
    end
  end

  # ── Commands ──────────────────────────────────────────────────────────────

  command "init", "Register project and run first full scan" do
    argument(:path, :string, default: "")
    flag(:help, :boolean, [])
    # v2.6.0 (Fase E): optional post-scan summarization.
    flag(:with_summary, :boolean, [])
    flag(:with_briefing, :boolean, [])
    # v2.7.0: --force forwards to delfos summarize when used with
    # --with-summary / --with-briefing. Re-generates summaries for
    # symbols that already have one (otherwise they're skipped).
    flag(:force, :boolean, [])
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
    flag(:kind, :string, [])
    flag(:level, :string, [])
    flag(:n, :integer, [])
    flag(:format, :string, [])
    flag(:llm_less, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :query_handler})
  end

  command "audit", "Technical debt: hotspots, cycles, instability" do
    flag(:file, :string, [])
    flag(:with_explanation, :boolean, [])
    flag(:llm_less, :boolean, [])
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
    flag(:llm_less, :boolean, [])
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
    flag(:with_explanation, :boolean, [])
    flag(:llm_less, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :agents_handler})
  end

  command "config", "Manage Delfos configuration (LLM, providers, models, theme)" do
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
    flag(:guided, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :doctor_handler})
  end

  command "status", "Index status and registered projects" do
    flag(:stats, :boolean, [])
    flag(:help, :boolean, [])
    run({Delfos.CLI, :status_handler})
  end

  command "mcp", "Start MCP stdio server (used by AI agents to query Delfos)" do
    run({Delfos.CLI, :mcp_handler})
  end

  command "version", "Show installed Delfos version + build info" do
    flag(:help, :boolean, [])
    flag(:json, :boolean, [])
    flag(:no_splash, :boolean, [])
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

    check_llm_guard(args, known_command?(args))

    # v2.6.0: handlers raise `Delfos.CLI.Abort` instead of calling
    # `System.halt(1)` directly. The dispatcher also raises on
    # unknown-command errors. We rescue here and convert to the right
    # exit code via `System.halt/1`.
    #
    # Why rescue HERE (and not in tests): ExUnit's CaptureIO doesn't
    # trap `System.halt` — it kills the VM. By raising an exception
    # that propagates to `main/1`, we let tests wrap calls in
    # `rescue e in Delfos.CLI.Abort` or `assert_raise`, while the
    # production entry point (the batamanta eScript) sees the same
    # exit codes as before. Win-win.
    #
    # The `with` is here instead of naked `try` because `check_llm_guard`
    # also raises (LLMGuard.check returns `{:halt, _}` for missing
    # endpoints, which we raise as Abort with code 78).
    try do
      result = dispatch_main(args)

      case result do
        {:error, _} ->
          raise Delfos.CLI.Abort, message: "dispatch error", code: 1

        _ ->
          :ok
      end
    rescue
      e in Delfos.CLI.Abort -> System.halt(e.code)
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
  defp check_llm_guard([first | rest], true) do
    # Skip the guard when the user is just asking for help or showing
    # the version — these are read-only operations that don't actually
    # need a running LLM.
    if "--help" in rest or "-h" in rest do
      :ok
    else
      case LLMGuard.check(first) do
        :ok -> :ok
        :warn -> :ok
        # v2.6.0: raise Delfos.CLI.Abort so tests can rescue. Exit
        # code 78 follows the convention of `delfos mcp`'s pre-flight.
        {:halt, _} -> raise Delfos.CLI.Abort, message: "LLM guard halted", code: 78
      end
    end
  end

  # v2.6.0: skip the LLM probe entirely when the command is unknown.
  # The dispatcher will print the "unknown command" error itself, and
  # probing an unreachable LLM for an invalid command adds 2-15s of
  # latency to typos like `delfos wach`.
  defp check_llm_guard(_args, _known?), do: :ok

  # Lazy: built on first call. `__commands__/0` is generated by Alaja
  # at compile time but module attributes can't depend on it cleanly,
  # so we build the set once per process and memoise via Process.put.
  defp known_command?([first | _rest]) do
    MapSet.member?(known_command_set(), first)
  end

  defp known_command?(_), do: false

  defp known_command_set do
    case Process.get({__MODULE__, :known_set}) do
      nil ->
        set = __commands__() |> Enum.map(& &1.name) |> MapSet.new()
        Process.put({__MODULE__, :known_set}, set)
        set

      set ->
        set
    end
  end

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
