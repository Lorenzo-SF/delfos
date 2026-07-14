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
    workers = Map.get(opts, :workers) || 4

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
      progress_bar = Alaja.Components.Progress.new(label: "Indexing", total: total)
      progress_cb = fn _idx, _total -> Alaja.Components.Progress.tick(progress_bar) end

      # Process in parallel via FileProcessor (which uses Arrea internally
      # for the actual file work). The progress bar is driven by
      # per-file completion notifications.
      {:ok, ok} =
        FileProcessor.process_files_with_progress(contents, project,
          on_progress: progress_cb
        )

      Alaja.Components.Progress.finish(progress_bar)
      Alaja.print_success("Indexed: #{ok}/#{total}")

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
