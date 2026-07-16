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

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  @doc """
  Runs a scan with pre-parsed options (no argv re-parse).
  Called directly by the CLI handler, avoiding the handler-bridge anti-pattern.

  ## Options

    * `:full` — boolean, re-process every file (default: false)
    * `:workers` — non_neg_integer, parallel workers (default: 4)
    * `:multi_bar` — GenServer.server() | nil, when set the scan drives
                     the given `Alaja.Components.MultiBar` instead of
                     drawing its own AnimatedBar. The bar's task id is
                     taken from `:scan_task_id` (default: `:scan`).
    * `:scan_task_id` — atom(), task id used when `:multi_bar` is set
                        (default: `:scan`)

  When `:multi_bar` is nil (the default), the scan runs with the
  existing AnimatedBar-driven progress in `FileProcessor` so direct
  `delfos scan` invocations look identical to v2.4.0.
  """
  def run_with_opts(opts) when is_map(opts) do
    full = Map.get(opts, :full, false)
    workers = Map.get(opts, :workers) || 4
    multi_bar = Map.get(opts, :multi_bar)
    scan_task_id = Map.get(opts, :scan_task_id, :scan)

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.inserted_at], limit: 1))

    unless project,
      do:
        (
          Alaja.print_error("No projects registered. Run: delfos init .")
          System.halt(1)
        )

    Alaja.print_info("Scanning: #{project.name} (#{if full, do: "full", else: "incremental"})")

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
      # Read contents
      contents =
        to_process
        |> Enum.flat_map(fn p ->
          case File.read(p) do
            {:ok, c} -> [{p, c}]
            _ -> []
          end
        end)

      total = length(contents)

      # Choose progress surface: MultiBar when init drove one, else
      # the legacy AnimatedBar that lives inside FileProcessor.
      fp_opts = build_file_processor_opts(contents, project, multi_bar, scan_task_id)
      {:ok, ok} = FileProcessor.process_files_with_progress(contents, project, fp_opts)

      # If a MultiBar is driving us, close out the scan task with
      # a final success line so the table shows "✓ Done" instead of
      # the partial progress bar.
      if multi_bar do
        Alaja.Components.MultiBar.success(multi_bar, scan_task_id, "#{ok}/#{total} files")
      else
        Alaja.print_success("Indexed: #{ok}/#{total}")
      end

      # Print a single summary of files that couldn't be embedded, instead
      # of one warning per file (which floods the scan log).
      FileProcessor.flush_embedding_unavailable()
    end

    Alaja.print_info("Building graph...")
    safely_build_graph(project)

    Alaja.print_info("Analyzing coupling and churn...")
    safely_analyze(project)

    elapsed = System.monotonic_time(:millisecond) - t0
    Alaja.print_success("Done in #{Float.round(elapsed / 1000, 1)}s")
  end

  # Build the opts passed to FileProcessor.process_files_with_progress/3.
  # When a MultiBar is in play, we DON'T want FileProcessor to draw its
  # own AnimatedBar (would clash with the MultiBar's table). Instead we
  # pass an :on_progress callback that drives the MultiBar task.
  defp build_file_processor_opts(_contents, _project, nil, _task_id),
    do: [label: "Indexing"]

  defp build_file_processor_opts(contents, _project, bar_pid, task_id) do
    total = length(contents)

    on_progress = fn idx, _total ->
      pct = if total > 0, do: trunc(idx / total * 100), else: 0
      Alaja.Components.MultiBar.progress(bar_pid, task_id, pct, "#{idx}/#{total} files")
    end

    [on_progress: on_progress, nocolor: true]
  end

  # Wrappers that catch errors from the secondary analyses so the
  # scan's last_scanned timestamp is always updated, even if
  # graph building or churn analysis crashes (e.g. when mix xref
  # fails in a subprocess with no Ecto repo available).
  defp safely_build_graph(project) do
    GraphBuilder.build(project)
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
