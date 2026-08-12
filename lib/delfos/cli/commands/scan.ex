defmodule Delfos.CLI.Commands.Scan do
  @moduledoc """
  Re-indexes the active project. Incremental by default, `--full` for everything.

  Output is rendered through `Alaja` so messages get icon prefixes
  consistent with the rest of the CLI.
  """

  import Ecto.Query
  require Logger

  alias Alaja
  alias Delfos.{Repo, Schema}
  alias Delfos.Indexer.{Scanner, FileProcessor, GraphBuilder}
  alias Delfos.Analysis.{CouplingAnalyzer, ChurnAnalyzer}
  alias Delfos.Config.Manager

  @help """
  USAGE
      delfos scan [flags]

  Re-index the active project.

  FLAGS
      --full          Re-process every file (ignore hash cache)
      --workers N     Parallel workers (default: 4, capped at 32)

  EXAMPLES
      delfos scan              # incremental
      delfos scan --full       # full re-index
      delfos scan --workers 8  # 8 parallel workers
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  # Legacy argv entry point — kept for backward compat.
  # New code should call `run_with_opts/1` instead.
  def run(args) when is_list(args) do
    {opts, _, _} =
      Alaja.CLI.OptionsParser.parse(args, %{switches: [full: :boolean, workers: :integer]})

    run_with_opts(opts)
  end

  @doc """
  Runs a scan with pre-parsed options (no argv re-parse).
  Called directly by the CLI handler, avoiding the handler-bridge anti-pattern.
  """
  def run_with_opts(opts) when is_map(opts) do
    full = Map.get(opts, :full, false)
    incremental = Map.get(opts, :incremental, false)
    workers = Map.get(opts, :workers) || 4
    force? = Map.get(opts, :force, false)

    # FE-5: --full y --incremental son mutuamente excluyentes. El
    # default (cuando ninguno se pasa) es incremental — esto
    # preserva el comportamiento histórico y hace que `--incremental`
    # sea seguro de añadir a scripts sin cambiar semántica.
    cond do
      full and incremental ->
        Alaja.print_error("--full and --incremental are mutually exclusive")
        System.halt(1)

      true ->
        :ok
    end

    # Si --incremental explícito, forzar incremental (sobrescribe full).
    full = full and not incremental

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.inserted_at], limit: 1))

    unless project,
      do:
        (
          Alaja.print_error("No projects registered. Run: delfos init .")
          System.halt(1)
        )

    # SE-1: re-validar el path del proyecto antes de scanear
    # (el path podría haber cambiado desde el init o el proyecto
    # podría haber sido movido a una zona sensible).
    case Delfos.Indexer.Sandbox.validate(project.path, force: force?) do
      :ok -> :ok
      {:error, reason} ->
        Alaja.print_error("Project path rejected on scan: #{reason}")
        Alaja.print_info("Use --force to override project-marker heuristic.")
        System.halt(1)
    end

    Alaja.print_info(
      "Scanning: #{project.name} (#{if full, do: "full", else: "incremental (hash-based)"})"
    )

    t0 = System.monotonic_time(:millisecond)
    ignore_dirs = Manager.indexing()[:ignore_dirs] || []
    files = Scanner.find_files(project.path, ignore_dirs)
    to_process = if full, do: files, else: Scanner.find_changed_files(files, project)

    # Update last_scanned as soon as the scan starts (not when it
    # finishes) so the timestamp is always meaningful, even if
    # the secondary analyses (graph build, churn) crash. Otherwise
    # 'delfos status' shows 'Last scan: never' for projects that
    # successfully indexed but then crashed during post-processing.
    project
    |> Schema.Project.changeset(%{last_scanned: DateTime.utc_now()})
    |> Repo.update!()

    Alaja.print_info("Files: #{length(files)} found, #{length(to_process)} to process")
    Alaja.print_info("Workers: #{workers} (use --workers N to change)")

    if length(to_process) > 0,
      do: Alaja.print_info("Indexing (this can take a while)...")

    unless Enum.empty?(to_process) do
      # P3: en incremental, el scanner ya leyó contenido y calculó hash
      # (`{path, content, hash}`). En full, el scanner solo devolvió paths
      # y tenemos que leer aquí.
      contents =
        if full do
          to_process
          |> Enum.flat_map(fn p ->
            case File.read(p) do
              {:ok, c} -> [{p, c}]
              _ -> []
            end
          end)
        else
          Enum.map(to_process, fn {path, content, _hash} -> {path, content} end)
        end

      total = length(contents)

      # Process in parallel via FileProcessor. With `:label`,
      # FileProcessor owns the `Alaja.Components.Progress` lifecycle
      # (new/tick/finish) so we don't have to manage it here.
      {:ok, ok} =
        FileProcessor.process_files_with_progress(contents, project, label: "Indexing")

      Alaja.print_success("Indexed: #{ok}/#{total}")

      # Print a single summary of files that couldn't be embedded, instead
      # of one warning per file (which floods the scan log).
      FileProcessor.flush_embedding_unavailable()
    end

    Alaja.print_info("Building graph...")
    # FE-6: pass changed paths so incremental scans don't rebuild
    # the whole graph. Full scans pass an empty list → triggers full
    # rebuild via safely_build_graph.
    changed_paths =
      case to_process do
        [_ | _] = items when not full ->
          # `to_process` in incremental mode is a list of
          # `{path, content, hash}` tuples (from find_changed_files/2).
          Enum.map(items, fn {path, _content, _hash} -> path end)

        _ ->
          []
      end

    safely_build_graph(project, changed_paths)

    Alaja.print_info("Analyzing coupling and churn...")
    safely_analyze(project)

    elapsed = System.monotonic_time(:millisecond) - t0
    Alaja.print_success("Done in #{Float.round(elapsed / 1000, 1)}s")
  end

  # Wrappers that catch errors from the secondary analyses so the
  # scan's last_scanned timestamp is always updated, even if
  # graph building or churn analysis crashes (e.g. when mix xref
  # fails in a subprocess with no Ecto repo available).
  #
  # FE-6: incremental graph rebuild. In full mode, all files need
  # their edges re-extracted (use build/1). In incremental mode,
  # only the changed files need it (use build_for_paths/3) — much
  # cheaper for big repos where most files don't change.
  defp safely_build_graph(project, changed_paths) do
    cond do
      changed_paths == [] ->
        GraphBuilder.build(project)

      true ->
        files_by_path =
          project.id
          |> files_in_project_query()
          |> Repo.all()
          |> Map.new(fn f -> {f.path, f} end)

        GraphBuilder.build_for_paths(project, changed_paths, files_by_path)
    end
  rescue
    e ->
      require Logger
      Logger.warning("[scan] graph build failed: #{Exception.message(e)}")
      :ok
  catch
    kind, reason ->
      require Logger
      Logger.warning("[scan] graph build #{kind}: #{inspect(reason)}")
      :ok
  end

  defp files_in_project_query(project_id) do
    from(f in Schema.File, where: f.project_id == ^project_id)
  end

  defp safely_analyze(project) do
    CouplingAnalyzer.analyze(project)
    ChurnAnalyzer.analyze(project)
  rescue
    e ->
      require Logger
      Logger.warning("[scan] analysis failed: #{Exception.message(e)}")
      :ok
  catch
    kind, reason ->
      require Logger
      Logger.warning("[scan] analysis #{kind}: #{inspect(reason)}")
      :ok
  end
end
