defmodule Delfos.Indexer.FileProcessor do
  @moduledoc """
  Procesa archivos: parsea con TreeSitter, genera embeddings en batch
  y persiste en DB. Usa Arrea.Parallel para concurrencia controlada.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}
  alias Delfos.Parsers.Dispatcher
  alias Delfos.Indexer.Chunker
  alias Delfos.LLM.Client

  @file_workers 4

  @spec process_files([{String.t(), binary()}], Schema.Project.t()) ::
          {:ok, non_neg_integer()}
  def process_files(file_list, project) do
    funs =
      Enum.map(file_list, fn {path, content} ->
        fn -> process_file(path, content, project) end
      end)

    # C-3 audit fix: Arrea.Parallel es @moduledoc false; usamos la fachada.
    results = Arrea.run_sync(funs, workers: @file_workers)

    # A-9 audit fix: contar :skipped como éxito (es un outcome válido).
    ok =
      Enum.count(results, fn
        {:ok, %{result: {:ok, _}}} -> true
        _ -> false
      end)

    Logger.info("FileProcessor: #{ok}/#{length(file_list)} procesados")
    {:ok, ok}
  end

  @doc """
  Same as `process_files/2` but with a progress bar. Uses
  `Alaja.Components.AnimatedBar` to render the progress in-place.

  The bar is drawn to stderr so it doesn't pollute stdout that may
  be piped. When `nocolor` is true (or stderr is not a TTY), the
  bar silently falls back to no output — just the existing log line
  at the end.
  """
  @spec process_files_with_progress(
          [{String.t(), binary()}],
          Schema.Project.t(),
          keyword()
        ) :: {:ok, non_neg_integer()}
  def process_files_with_progress(file_list, project, opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress)
    nocolor = Keyword.get(opts, :nocolor, false)

    cond do
      not is_function(on_progress, 2) ->
        process_files(file_list, project)

      nocolor or not tty?(:stderr) ->
        # No terminal / no TTY: just run silently. Caller already
        # printed the "Indexed: X/Y" line, so we don't add noise.
        funs =
          Enum.map(file_list, fn {path, content} ->
            fn -> process_file(path, content, project) end
          end)

        results = Arrea.run_sync(funs, workers: @file_workers)
        ok = Enum.count(results, fn {:ok, %{result: {:ok, _}}} -> true; _ -> false end)
        {:ok, ok}

      true ->
        do_with_progress(file_list, project, on_progress)
    end
  end

  defp do_with_progress(file_list, project, on_progress) do
    total = length(file_list)
    on_progress.(0, total)

    # We use Task.async_stream directly here (instead of Arrea.run_sync)
    # because we need a per-task completion callback to drive the
    # progress bar. Arrea.run_sync returns all results at the end,
    # which is useless for progress. This still uses the same worker
    # count as the no-progress path.
    ok =
      file_list
      |> Task.async_stream(
        fn {path, content} -> process_file(path, content, project) end,
        max_concurrency: @file_workers,
        timeout: 60_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce(0, fn
        {:ok, {:ok, _file_or_status}}, acc ->
          on_progress.(-1, total)
          acc + 1

        {:ok, _other}, acc ->
          on_progress.(-1, total)
          acc

        {:exit, _reason}, acc ->
          on_progress.(-1, total)
          acc
      end)

    on_progress.(total, total)
    Logger.info("FileProcessor: #{ok}/#{total} procesadas")
    {:ok, ok}
  end

  defp tty?(:stderr) do
    case :io.getopts(:standard_error) do
      {:ok, opts} -> Keyword.get(opts, :tty, false)
      _ -> false
    end
  end

  @spec process_file(String.t(), binary(), Schema.Project.t()) ::
          {:ok, Schema.File.t() | :skipped} | {:error, term()}
  def process_file(path, content, project) do
    with {:ok, parsed} <- Dispatcher.parse(path, content),
         {:ok, file} <- upsert_file(path, content, parsed, project) do
      process_symbols(parsed.symbols, file, project, content)
      process_chunks(content, file, project)
      {:ok, file}
    else
      {:error, :unsupported_extension} ->
        {:ok, :skipped}

      {:error, reason} ->
        Logger.warning("FileProcessor error #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_symbols([], _f, _p, _c), do: :ok

  defp process_symbols(raw_symbols, file, project, content) do
    symbols = Enum.map(raw_symbols, &extract_symbol_content(&1, content))
    texts = Enum.map(symbols, &build_embed_text/1)
    embeds = Client.embed_batch(texts)
    check_length_match("symbols", symbols, embeds)

    Enum.zip_with(symbols, embeds, fn sym, emb ->
      upsert_symbol(sym, file, project, emb)
    end)
  end

  defp extract_symbol_content(sym, content) do
    lines = String.split(content, "\n")
    s = max(0, (sym.line_start || 1) - 1)
    e = min(length(lines) - 1, (sym.line_end || sym.line_start || 1) - 1)

    # `s..e` raises ArgumentError if s > e (e.g. line_start == line_end == 0).
    # Use a safe range construction.
    sliced =
      if s <= e do
        Enum.slice(lines, s..e)
      else
        []
      end

    Map.put(sym, :content, Enum.join(sliced, "\n"))
  end

  defp build_embed_text(sym) do
    [
      sym.kind,
      sym.qualified_name || sym.name,
      sym.signature,
      sym.docstring,
      sym.content && String.slice(sym.content, 0, 600)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp upsert_symbol(sym, file, project, embedding) do
    existing =
      Repo.one(
        from(s in Schema.Symbol,
          where:
            s.file_id == ^file.id and s.name == ^(sym.name || "") and
              s.line_start == ^(sym.line_start || 0)
        )
      )

    attrs = %{
      file_id: file.id,
      project_id: project.id,
      name: sym.name || "",
      qualified_name: sym.qualified_name || sym.name || "",
      kind: sym.kind || "unknown",
      visibility: sym.visibility || "public",
      line_start: sym.line_start,
      line_end: sym.line_end,
      signature: sym.signature,
      docstring: sym.docstring,
      content: sym.content,
      language: sym.language || Dispatcher.language(file.path),
      metadata: sym.metadata || %{},
      embedding: embedding
    }

    changeset =
      if existing do
        Schema.Symbol.changeset(existing, attrs)
      else
        Schema.Symbol.changeset(%Schema.Symbol{}, attrs)
      end

    case Repo.insert_or_update(changeset) do
      {:ok, _} -> :ok
      {:error, cs} -> Logger.warning("upsert_symbol: #{inspect(cs.errors)}")
    end
  end

  defp process_chunks(content, file, project) do
    chunks = Chunker.chunk_by_size(content, max_tokens: 512)

    embeds = Client.embed_batch(Enum.map(chunks, & &1.content))

    if Enum.any?(embeds, &is_nil/1) do
      # Embedding provider is down or returned nil for some chunks.
      # Without dedup, a project with 200 files and no LLM running
      # would log 200 identical warning lines. We count once and
      # surface a single line at the end of the scan via the
      # :persistent_term counter.
      bump_embedding_unavailable(file.path)
      {:error, :embedding_unavailable}
    else
      Repo.delete_all(from(c in Schema.Chunk, where: c.file_id == ^file.id))
      check_length_match("chunks", chunks, embeds)

      chunks
      |> Enum.zip_with(embeds, fn chunk, emb -> {chunk, emb} end)
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {{chunk, emb}, idx}, _acc ->
        attrs = %{
          file_id: file.id,
          project_id: project.id,
          content: chunk.content,
          line_start: chunk.line_start,
          line_end: chunk.line_end,
          chunk_index: idx,
          token_count: chunk.token_count,
          embedding: emb
        }

        case Repo.insert(Schema.Chunk.changeset(%Schema.Chunk{}, attrs)) do
          {:ok, _} ->
            {:cont, :ok}

          {:error, cs} ->
            Logger.warning("process_chunks #{file.path} chunk #{idx}: #{inspect(cs.errors)}")
            {:halt, {:error, cs}}
        end
      end)

      # Continue even if some chunks fail — partial index is better than none.
      :ok
    end
  rescue
    e -> Logger.warning("process_chunks #{file.path}: #{Exception.message(e)}")
  end

  defp upsert_file(path, content, parsed, project) do
    hash = compute_hash(content)

    stat =
      try do
        File.stat!(path)
      rescue
        _ -> %File.Stat{size: 0, mtime: nil}
      end

    existing = Repo.get_by(Schema.File, project_id: project.id, path: path)

    attrs = %{
      project_id: project.id,
      path: path,
      language: parsed[:language] || Dispatcher.language(path),
      size_bytes: stat.size,
      line_count: parsed.line_count,
      last_modified: stat.mtime && NaiveDateTime.from_erl!(stat.mtime),
      last_indexed: DateTime.utc_now() |> DateTime.to_naive(),
      content_hash: hash
    }

    changeset =
      if existing do
        Schema.File.changeset(existing, attrs)
      else
        Schema.File.changeset(%Schema.File{}, attrs)
      end

    case Repo.insert_or_update(changeset) do
      {:ok, file} ->
        {:ok, file}

      {:error, cs} ->
        Logger.error("upsert_file #{path}: #{inspect(cs.errors)}")
        {:error, cs}
    end
  end

  def compute_hash(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp check_length_match(label, list_a, list_b) do
    len_a = length(list_a)
    len_b = length(list_b)

    if len_a != len_b do
      Logger.warning(
        "FileProcessor: #{label} length mismatch: #{len_a} items vs #{len_b} embeddings. " <>
          "Truncating to shorter list."
      )
    end
  end

  # Counter for files where the embedding provider was unavailable.
  # Stored in :persistent_term so parallel workers can bump it
  # without contention. `flush_embedding_unavailable/0` is called
  # once at the end of the scan to print a single summary line.
  @embedding_unavailable_key {__MODULE__, :embedding_unavailable}

  defp bump_embedding_unavailable(path) do
    current = :persistent_term.get(@embedding_unavailable_key, [])
    :persistent_term.put(@embedding_unavailable_key, [path | current])
  end

  @doc """
  Prints a single summary of the files that had no embedding, and
  resets the counter. Call once at the end of the scan (e.g. in
  the CLI command's done handler).
  """
  def flush_embedding_unavailable do
    case :persistent_term.get(@embedding_unavailable_key, nil) do
      nil ->
        :ok

      [] ->
        :ok

      paths ->
        count = length(paths)
        sample = Enum.take(paths, 3) |> Enum.join(", ")

        Logger.warning(
          "Embedding unavailable for #{count} files. Sample: #{sample}. " <>
            "If this is unexpected, run 'delfos doctor' to check the LLM endpoint."
        )

        :persistent_term.erase(@embedding_unavailable_key)
    end
  end
end
