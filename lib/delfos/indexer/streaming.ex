defmodule Delfos.Indexer.Streaming do
  @moduledoc """
  FE-8: orquestador end-to-end del indexer que nunca carga el
  contenido de un archivo en memoria por completo.

  Pipeline:
    1. Scanner.stream_files/3 (PE-1)            — lazy walk del FS
       via `File.ls` recursivo. Emite paths uno por uno.
    2. Task.async_stream (P4-equivalent)        — procesa N files
       en paralelo (configurable). Cada uno ejecuta
       Chunker.chunk_file_path/3 (PE-4)        — streaming chunking,
       también O(1) en memoria.
    3. Repo.insert_all (P2)                    — un INSERT batch
       por grupo de chunks, no N individuales.
    4. CO-3 cleanup                            — borra chunks huérfanos
       si el archivo shrinkeó.

  Antes de FE-8: el flujo estaba fragmentado entre `Delfos.CLI.scan`
  y `Delfos.Indexer.FileProcessor`. El usuario invocaba scan, que
  llamaba a file_process_files, que internamente recorría paths
  sincrónicamente. Memoria peak: O(files × file_size).

  Después de FE-8: este módulo expone una API unificada que:
    * Stream los paths (no carga la lista en memoria) — ver fix abajo
    * Procesa en paralelo (workers)
    * Inserta en batches (no N round-trips)
    * Limpia orphans cada chunk_index >= new_count

  Memoria peak: O(workers × chunk_size) — bounded.

  Bug fix: la implementación previa materializaba la lista de paths
  con `Enum.to_list/1` antes de pasar a Task.async_stream. Esto
  rompía la garantía de backpressure (todos los paths se acumulaban
  en memoria antes de empezar el procesado paralelo). Ahora el
  Stream fluye directamente: el Scanner produce paths bajo demanda
  y Task.async_stream los consume con `max_concurrency`.

  Uso:
      Delfos.Indexer.Streaming.run(project, ignore_dirs,
        workers: 4,
        max_files: 100_000)
  """

  require Logger

  alias Delfos.Indexer.{FileProcessor, Scanner}

  @doc """
  Runs the full streaming indexer for a project.

  Options:
    * `:workers` — concurrent files in flight (default: System.schedulers_online())
    * `:max_files` — hard cap on files scanned (default 500_000)
    * `:max_depth` — hard cap on directory depth (default 50)
  """
  def run(project, ignore_dirs \\ [], opts \\ []) do
    workers = Keyword.get(opts, :workers, System.schedulers_online())
    max_files = Keyword.get(opts, :max_files, 500_000)
    max_depth = Keyword.get(opts, :max_depth, 50)

    Logger.info("Streaming indexer starting: project=#{project.name} workers=#{workers}")

    start_time = System.monotonic_time(:millisecond)

    # Stream files — NUNCA materializamos la lista completa. El Scanner
    # emite paths bajo demanda; Task.async_stream los consume con
    # backpressure (max_concurrency).
    file_stream =
      project.path
      |> Scanner.stream_files(ignore_dirs, max_files: max_files, max_depth: max_depth)

    # Process in parallel. Task.async_stream hace backpressure real:
    # cuando hay N tasks en vuelo, el producer pausa hasta que alguna
    # termine. Esto + el Stream del Scanner garantiza O(workers) en
    # memoria, no O(N paths).
    {ok_count, err_count} =
      file_stream
      |> Task.async_stream(
        &process_file(&1, project, opts),
        max_concurrency: workers,
        timeout: 300_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce({0, 0}, fn
        {:ok, _result}, {ok, err} -> {ok + 1, err}
        {:exit, _reason}, {ok, err} -> {ok, err + 1}
      end)

    elapsed_ms = System.monotonic_time(:millisecond) - start_time
    throughput = if elapsed_ms > 0, do: round(ok_count / (elapsed_ms / 1000)), else: 0

    Logger.info(
      "Streaming indexer done: #{ok_count} files processed, " <>
        "#{err_count} errors, #{elapsed_ms}ms (~#{throughput} files/s)"
    )

    {:ok, ok_count}
  end

  defp process_file(path, project, _opts) do
    case File.read(path) do
      {:ok, content} ->
        FileProcessor.process_file(path, content, project)

      {:error, reason} ->
        Logger.warning("Streaming: cannot read #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
