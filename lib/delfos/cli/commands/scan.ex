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

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [full: :boolean, workers: :integer])
    full = opts[:full] || false
    workers = opts[:workers] || 4

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

    Alaja.print_info("Files: #{length(files)} found, #{length(to_process)} to process")

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

      # Process in parallel via Arrea (public facade)
      funs =
        Enum.map(contents, fn {path, content} ->
          fn -> FileProcessor.process_file(path, content, project) end
        end)

      results = Arrea.run_sync(funs, workers: workers)

      ok =
        Enum.count(results, fn
          {:ok, %{result: {:ok, _}}} -> true
          _ -> false
        end)

      Alaja.print_success("Indexed: #{ok}/#{length(funs)}")

      Alaja.print_info("Building graph...")
      GraphBuilder.build(project)

      Alaja.print_info("Analyzing coupling and churn...")
      CouplingAnalyzer.analyze(project)
      ChurnAnalyzer.analyze(project)

      elapsed = System.monotonic_time(:millisecond) - t0
      Alaja.print_success("Done in #{Float.round(elapsed / 1000, 1)}s")

      project
      |> Schema.Project.changeset(%{last_scanned: DateTime.utc_now()})
      |> Repo.update!()
    end
  end
end
