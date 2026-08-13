defmodule Delfos.Indexer.Streaming do
  @moduledoc """
  FE-8: orquestador end-to-end del indexer que nunca carga el
  contenido de un archivo en memoria por completo.

  Two-stage pipeline (v2.3.0+):

    Stage 1 (CPU-bound):  scan + parse + extract embed text per file
                          → produces `payloads` (no embedding yet)
                          → workers = :parse_workers (default schedulers)

    Stage 2 (I/O-bound):  embed_batch(payload texts) + persist to DB
                          → 1 HTTP roundtrip per file (combined symbols+chunks)
                          → workers = :embed_workers (default 2× schedulers, capped at 32)

  Why two stages? With single-stage Task.async_stream, the slowest file's
  embed latency blocks a worker that's idle waiting for the embed call.
  With two stages, Stage 1 finishes parsing all files quickly (CPU-bound,
  scales with cores) and Stage 2 fans out into more workers for the
  embedding roundtrips (I/O-bound, scales with the HTTP/Finch pool size
  and Ollama's parallel capacity).

  Backpressure: Task.async_stream pauses the producer when N tasks are
  in flight, so memory stays O(workers) even if files take long.

  Uso:
      Delfos.Indexer.Streaming.run(project, ignore_dirs,
        parse_workers: 8,
        embed_workers: 24,
        max_files: 100_000)
  """

  require Logger

  alias Delfos.Indexer.{FileProcessor, Scanner}

  @default_parse_workers System.schedulers_online()
  # Embeds go via HTTP to Ollama; 2× schedulers is usually safe (Finch
  # pool default = 50). Cap at 32 to avoid swamping small LLM servers.
  @default_embed_workers min(System.schedulers_online() * 2, 32)
  @default_max_files 500_000
  @default_max_depth 50

  @doc """
  Runs the full streaming indexer for a project.

  Options:
    * `:parse_workers` — concurrent files parsing in Stage 1
      (default: System.schedulers_online())
    * `:embed_workers` — concurrent files embedding in Stage 2
      (default: min(schedulers * 2, 32))
    * `:max_files` — hard cap on files scanned (default 500_000)
    * `:max_depth` — hard cap on directory depth (default 50)
  """
  def run(project, ignore_dirs \\ [], opts \\ []) do
    parse_workers = Keyword.get(opts, :parse_workers, @default_parse_workers)
    embed_workers = Keyword.get(opts, :embed_workers, @default_embed_workers)
    max_files = Keyword.get(opts, :max_files, @default_max_files)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)

    Logger.info(
      "Streaming indexer starting: project=#{project.name} " <>
        "parse_workers=#{parse_workers} embed_workers=#{embed_workers}"
    )

    start_time = System.monotonic_time(:millisecond)

    file_stream =
      project.path
      |> Scanner.stream_files(ignore_dirs, max_files: max_files, max_depth: max_depth)

    # Stage 1: scan + parse + extract payloads (CPU-bound, fast)
    stage1_start = System.monotonic_time(:millisecond)

    payloads =
      file_stream
      |> Task.async_stream(
        &stage1_parse(&1, project),
        max_concurrency: parse_workers,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, list} -> list
        {:exit, _} -> []
      end)

    stage1_ms = System.monotonic_time(:millisecond) - stage1_start
    Logger.info("Stage 1 (parse): #{length(payloads)} payloads in #{stage1_ms}ms")

    # Stage 2: embed + persist (I/O-bound, slow)
    stage2_start = System.monotonic_time(:millisecond)

    persisted =
      payloads
      |> Task.async_stream(
        &stage2_embed_persist(&1),
        max_concurrency: embed_workers,
        timeout: 300_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce({0, 0}, fn
        {:ok, :ok}, {ok, err} -> {ok + 1, err}
        {:ok, {:error, _}}, {ok, err} -> {ok, err + 1}
        {:exit, _}, {ok, err} -> {ok, err + 1}
      end)

    {ok_count, err_count} = persisted
    stage2_ms = System.monotonic_time(:millisecond) - stage2_start

    elapsed_ms = System.monotonic_time(:millisecond) - start_time
    throughput = if elapsed_ms > 0, do: round(ok_count / (elapsed_ms / 1000)), else: 0

    Logger.info(
      "Streaming indexer done: #{ok_count} files indexed, " <>
        "#{err_count} errors, total=#{elapsed_ms}ms " <>
        "(stage1=#{stage1_ms}ms / stage2=#{stage2_ms}ms) (~#{throughput} files/s)"
    )

    {:ok, ok_count}
  end

  # Stage 1: read file + parse + extract embed payloads (no I/O).
  # Returns a list of payloads, one per symbol + chunk.
  defp stage1_parse(path, project) do
    case File.read(path) do
      {:ok, content} ->
        FileProcessor.extract_payloads_only(path, content, project)

      {:error, reason} ->
        Logger.warning("Streaming: cannot read #{path}: #{inspect(reason)}")
        []
    end
  end

  # Stage 2: embed all payloads from one file + persist.
  # Receives the list of payloads from Stage 1.
  defp stage2_embed_persist(payloads) do
    case FileProcessor.embed_and_persist_payloads(payloads) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end
end
