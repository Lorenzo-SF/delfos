defmodule Delfos.CLI.Commands.Init do
  @moduledoc """
  Registers a project and runs the first full scan.

  Output is rendered through `Alaja` (icon-prefixed messages, raw
  sections where formatting isn't needed). When stderr is a TTY, the
  scan step is wrapped in an `Alaja.Components.MultiBar` showing the
  file-by-file progress (driven by `FileProcessor`).

  ## Internal pipeline

  The `run/1` entry point delegates to a small set of named helpers
  so each step is testable in isolation and the dispatcher stays
  readable:

      run/1
        ├── ensure_booted/0              # apps, HTTP, DB
        ├── resolve_target_path/1        # args → absolute path
        ├── gather_project_metadata/1    # stack + git
        ├── ensure_llm_ready/0           # pre-flight so the scan doesn't die
        ├── register_or_resolve/3        # new vs handle_existing
        ├── apply_action/2               # :new | :keep | :wipe | :cancel
        │     └── with_multi_bar/1       # wraps scan + analysis in MultiBar
        └── print_next_steps/1           # friendly outro
  """

  alias Alaja
  alias Alaja.Components.MultiBar
  alias Delfos.{Repo, Schema}
  alias Delfos.CLI.Errors
  alias Trebejo.Util

  @help """
  USAGE
      delfos init [path]

  Register a project and run the first full scan.

  ARGUMENTS
      path           Directory to index (default: current directory)

  EXAMPLES
      delfos init .
      delfos init ~/code/my-app

  After init you'll see the recommended next steps.
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  def run_with_opts(%{help: true}) do
    Alaja.print_raw(help_text())
  end

  def run_with_opts(%{path: path}) do
    ensure_booted()

    path = resolve_target_path([path])
    {:ok, info} = gather_project_metadata(path)
    %{} = project_info = Map.put(info, :path, path)
    name = Path.basename(path)

    print_init_header(name, project_info)
    ensure_llm_ready()

    action = register_or_resolve(path, project_info)
    apply_action(action, name)
    print_next_steps(name)
  end

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) when is_list(args) do
    cond do
      "--help" in args or "-h" in args ->
        Alaja.print_raw(help_text())

      true ->
        run_with_opts(%{path: List.first(args) || ""})
    end
  end

  # ============================================================================
  # Boot
  # ============================================================================

  # Boots the OTP application, the HTTP transport (Finch pool) and the
  # Ecto repository. Halts with exit 1 on DB failure. Idempotent — safe to
  # call multiple times in the same VM.
  defp ensure_booted do
    # Ensure OTP app is running (starts RepoStarter, Ecto repo, etc.)
    Application.ensure_all_started(:delfos)

    # Guard: some release boot paths may not have started Finch yet.
    Apero.Http.Finch.ensure_started()

    case Delfos.RepoStarter.start_repo() do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Errors.abort(
          ["delfos", "init", "ensure_booted", "repo_starter"],
          "Database not available: #{reason}",
          hint: "Run: delfos config setup db"
        )
    end
  end

  # ============================================================================
  # Path resolution
  # ============================================================================

  # Returns an absolute path. Defaults to the cwd when no positional arg
  # is given. Halts with exit 1 when the path isn't a directory.
  defp resolve_target_path([]), do: resolve_target_path([File.cwd!()])

  defp resolve_target_path([arg | _rest]) do
    path = Path.expand(arg)

    unless File.dir?(path) do
      Errors.abort(
        ["delfos", "init", "resolve_target_path"],
        "Path does not exist or is not a directory: #{path}",
        hint: "Pass an existing directory, or omit the path to use the current working directory"
      )
    end

    path
  end

  # ============================================================================
  # Project metadata
  # ============================================================================

  # Discovers all the metadata we cache on `Schema.Project`. Pure-ish:
  # it does filesystem + git reads but no DB writes. Returns
  # `{:ok, map}` so callers can pattern-match on success without
  # remembering the field list.
  defp gather_project_metadata(path) do
    {:ok,
     %{
       primary_stack: detect_primary_stack(path),
       all_stacks: detect_all_stacks(path),
       git_remote: read_git(path, ["remote", "get-url", "origin"]),
       git_branch: read_git(path, ["rev-parse", "--abbrev-ref", "HEAD"]),
       last_commit: read_git(path, ["rev-parse", "--short", "HEAD"])
     }}
  end

  defp print_init_header(name, project_info) do
    Alaja.print_info("Initializing: #{name}")

    Alaja.print_raw(
      "  Stack: #{project_info.primary_stack} | " <>
        "Stacks: #{Enum.join(project_info.all_stacks, ", ")}\n"
    )

    Alaja.print_raw(
      "  Git: #{project_info.git_branch || "—"} @ #{project_info.last_commit || "—"}\n"
    )
  end

  # ============================================================================
  # LLM pre-flight
  # ============================================================================

  # LLMDiscovery debe correr ANTES del scan (no después) porque el scan
  # necesita los LLMs para generar embeddings de los chunks. Antes, si
  # los LLMs estaban caídos, el scan fallaba con 'embedding unavailable'
  # para cada chunk. Ahora arrancamos los LLMs automáticamente (en modo
  # no-interactivo) o preguntamos al usuario antes de empezar a indexar.
  defp ensure_llm_ready do
    case Delfos.Config.LLMDiscovery.ensure_embedding_server(yes: true) do
      :started ->
        Alaja.print_success("Embed server started")

      :already_running ->
        :ok

      :not_applicable ->
        :ok

      {:error, reason} ->
        Alaja.print_warning(
          "Embed server could not start: #{inspect(reason)}. Continuing without it."
        )
    end

    Delfos.Config.LLMDiscovery.ensure_running(yes: true)
  end

  # ============================================================================
  # Register / resolve existing project
  # ============================================================================

  # Decide project action. If new, insert and return :new. If existing,
  # ask user (Keep / Wipe / Cancel) via `handle_existing_project/2`.
  # The returned action drives `apply_action/2` downstream.
  defp register_or_resolve(path, project_info) do
    case Repo.get_by(Schema.Project, path: path) do
      nil ->
        register_new_project(path, project_info)
        :new

      %Schema.Project{} = existing ->
        handle_existing_project(existing, project_info)
    end
  end

  defp register_new_project(path, project_info) do
    Repo.insert!(
      Schema.Project.changeset(%Schema.Project{}, %{
        name: Path.basename(path),
        path: path,
        primary_stack: project_info.primary_stack,
        all_stacks: project_info.all_stacks,
        git_remote: project_info.git_remote,
        git_branch: project_info.git_branch,
        last_commit: project_info.last_commit
      })
    )
  end

  defp handle_existing_project(existing, project_info) do
    Alaja.print_warning("Project already exists in the index (id=#{existing.id}).")
    Alaja.print_raw("\n")
    Alaja.print_info("Current state:")
    Alaja.print_raw("  Path:        #{existing.path}\n")
    Alaja.print_raw("  Stack:       #{existing.primary_stack}\n")
    Alaja.print_raw("  Last scan:   #{existing.last_scanned || "never"}\n")
    Alaja.print_raw("\n")

    case Alaja.Printer.Interactive.question_with_options(
           "Project is already indexed. What do you want to do?",
           [
             {"Keep existing data, just refresh metadata", :keep},
             {"Wipe and re-index from scratch (delete all symbols/files)", :wipe},
             {"Cancel init", :cancel}
           ],
           # Default to :keep on bare Enter so this command is non-interactive
           # in CI / piped contexts (e.g. `echo | delfos init .`).
           default: 1
         ) do
      :keep ->
        keep_existing(existing, project_info)

      :wipe ->
        wipe_existing(existing, project_info)

      :cancel ->
        Alaja.print_warning("Init cancelled.")
        :cancel

      :error ->
        # Non-interactive context (no TTY). Default to keeping existing data.
        Alaja.print_warning("Non-interactive mode: keeping existing data; updating metadata.")
        keep_existing(existing, project_info)
    end
  end

  defp keep_existing(existing, project_info) do
    Alaja.print_info("Keeping existing data; updating metadata...")

    Repo.update!(
      Schema.Project.changeset(existing, %{
        primary_stack: project_info.primary_stack,
        all_stacks: project_info.all_stacks,
        git_remote: project_info.git_remote,
        git_branch: project_info.git_branch,
        last_commit: project_info.last_commit
      })
    )

    :keep
  end

  defp wipe_existing(existing, project_info) do
    Alaja.print_info("Wiping existing data...")
    wipe_project(existing.id)

    Repo.update!(
      Schema.Project.changeset(existing, %{
        primary_stack: project_info.primary_stack,
        all_stacks: project_info.all_stacks,
        git_remote: project_info.git_remote,
        git_branch: project_info.git_branch,
        last_commit: project_info.last_commit
      })
    )

    :wipe
  end

  defp wipe_project(project_id) do
    # Delete in dependency order. Children first, then parents.
    import Ecto.Query

    Repo.delete_all(from(s in Delfos.Schema.Symbol, where: s.project_id == ^project_id))
    Repo.delete_all(from(c in Delfos.Schema.Chunk, where: c.project_id == ^project_id))
    Repo.delete_all(from(s in Delfos.Schema.Summary, where: s.project_id == ^project_id))
    Repo.delete_all(from(r in Delfos.Schema.Relationship, where: r.project_id == ^project_id))
    Repo.delete_all(from(m in Delfos.Schema.FileMetrics, where: m.project_id == ^project_id))
    Repo.delete_all(from(f in Delfos.Schema.File, where: f.project_id == ^project_id))
    Alaja.print_success("All indexed data wiped.")
  end

  # ============================================================================
  # Apply the chosen action
  # ============================================================================

  # Bug #19 fix: antes, después de handle_existing_project el código
  # SIEMPRE hacía Scan.run_with_opts(%{full: true}), contradiciendo el
  # mensaje 'Keeping existing data; updating metadata...'. Ahora la
  # acción retornada (que es :new/:keep/:wipe/:cancel) determina si se
  # hace un full re-scan.
  #
  # v2.5.0: el scan se envuelve en un Alaja.Components.MultiBar para dar
  # feedback visual por archivo. El bar se inicia aquí, se pasa a
  # Scan.run_with_opts/2 vía el opts map (:multi_bar, :scan_task_id),
  # y se cierra con MultiBar.done/1 al terminar.
  defp apply_action(:new, _name), do: run_scan_with_bar()

  defp apply_action(:wipe, _name), do: run_scan_with_bar()

  defp apply_action(:keep, _name) do
    # Refresh last_scanned para que el dashboard refleje la
    # decisión del usuario. No re-indexamos los archivos.
    Alaja.print_info("Skipping scan (use 'delfos scan --full' to re-index).")
  end

  defp apply_action(:cancel, _name) do
    System.halt(0)
  end

  # Starts a MultiBar (when stderr is a TTY) and runs the scan. The
  # bar drives `FileProcessor` via a progress callback that maps
  # (idx, total) → MultiBar.progress(pid, :scan, pct, desc).
  #
  # On non-TTY contexts (CI, piped output, docker logs) the bar is
  # skipped: FileProcessor.process_files_with_progress/3 falls back
  # to its no-bar path automatically because we don't pass the
  # `:multi_bar` opt and we don't pass `:label` either. The scan
  # output still includes the existing "Indexed: X/Y" success line.
  defp run_scan_with_bar do
    Alaja.print_raw("\n")
    Alaja.print_info("Starting full scan...")

    case start_multi_bar() do
      {:ok, bar_pid} ->
        try do
          Delfos.CLI.Commands.Scan.run_with_opts(%{
            full: true,
            multi_bar: bar_pid,
            scan_task_id: :scan
          })
        after
          MultiBar.done(bar_pid)
        end

      :no_tty ->
        Delfos.CLI.Commands.Scan.run_with_opts(%{full: true})
    end
  end

  # Starts a MultiBar GenServer with the scan task. Returns :no_tty
  # when stderr isn't a terminal (CI / piped) so the caller can fall
  # back to the bar-less scan path.
  #
  # Future v2.5.x: pre-allocate slots for `:summary` and `:briefing`
  # when `delfos init --with-summary` lands (Fase E). The MultiBar
  # header already supports multiple tasks so the layout won't
  # change.
  @doc false
  def start_multi_bar do
    if tty?(:stderr) do
      {:ok, pid} =
        MultiBar.start_link(
          tasks: [
            %{id: :scan, label: "Scanning", description: "Indexing files…"}
          ],
          title: "Delfos init — full scan",
          table_border: :rounded
        )

      {:ok, pid}
    else
      :no_tty
    end
  end

  defp tty?(:stderr) do
    case :io.getopts(:standard_error) do
      {:ok, opts} -> Keyword.get(opts, :tty, false)
      _ -> false
    end
  end

  # ============================================================================
  # Outro
  # ============================================================================

  defp print_next_steps(name) do
    Alaja.print_raw("\n")
    Alaja.print_info("Checking local LLM services...")
    Delfos.Config.LLMDiscovery.ensure_running()

    Alaja.print_success("#{name} indexed. Next steps:")

    Alaja.print_raw("""

        delfos summarize          # generate LLM summaries
        delfos integrate all --yes # configure AI agents
        delfos mcp &               # start MCP server
        delfos query "..."        # search the index
    """)
  end

  # ============================================================================
  # Stack detection
  # ============================================================================

  @doc false
  def detect_primary_stack(path) do
    cond do
      File.exists?("#{path}/mix.exs") -> "elixir"
      File.exists?("#{path}/Cargo.toml") -> "rust"
      File.exists?("#{path}/go.mod") -> "go"
      File.exists?("#{path}/pyproject.toml") or File.exists?("#{path}/setup.py") -> "python"
      File.exists?("#{path}/package.json") -> "node"
      File.exists?("#{path}/pom.xml") or File.exists?("#{path}/build.gradle") -> "java"
      File.exists?("#{path}/pubspec.yaml") -> "dart"
      File.exists?("#{path}/Gemfile") -> "ruby"
      File.exists?("#{path}/composer.json") -> "php"
      true -> "unknown"
    end
  end

  @doc false
  def detect_all_stacks(path) do
    [
      {"elixir", "mix.exs"},
      {"rust", "Cargo.toml"},
      {"go", "go.mod"},
      {"python", "pyproject.toml"},
      {"node", "package.json"},
      {"java", "pom.xml"},
      {"dart", "pubspec.yaml"},
      {"ruby", "Gemfile"},
      {"php", "composer.json"}
    ]
    |> Enum.filter(fn {_, f} -> File.exists?("#{path}/#{f}") end)
    |> Enum.map(fn {s, _} -> s end)
    |> case do
      [] -> ["unknown"]
      s -> s
    end
  end

  # ============================================================================
  # Git helpers (private)
  # ============================================================================

  defp read_git(path, args) do
    case Util.run_cmd_legacy("git", ["-C", path] ++ args, timeout: 5_000) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end
end
