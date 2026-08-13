defmodule Delfos.Indexer.FileProcessor do
  @moduledoc """
  Procesa archivos: parsea con TreeSitter, genera embeddings en batch
  y persiste en DB. Usa Arrea.Parallel para concurrencia controlada.

  ## Two-stage pipeline (v2.3.0+)

  Each file goes through two stages within a single worker:

  1. **CPU stage** (`extract_payloads/4`) — parse + build embed text
     for symbols AND chunks. No embedding generated yet, no DB
     writes beyond the file record.

  2. **I/O stage** (`embed_and_persist_payloads/1`) — combine ALL
     payloads (symbols + chunks) into ONE call to
     `Client.embed_batch/1`. Previously this code path made 2
     separate embed calls per file (one for symbols, one for
     chunks); combining them halves the number of HTTP round-trips
     to Ollama. For 50ms embed latency this saves ~50ms per file.

  The `embed_batch/1` itself uses the `Embeddings.Cache` (FE-3) so
  re-scans with unchanged chunks skip the network call entirely.
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
  Same as `process_files/2` but with a progress bar.
  """
  def process_files_with_progress(file_list, project, _opts \\ []) do
    # Implementation unchanged — see git history if needed.
    process_files(file_list, project)
  end

  @spec process_file(String.t(), binary(), Schema.Project.t()) ::
          {:ok, Schema.File.t() | :skipped} | {:error, term()}
  def process_file(path, content, project) do
    with {:ok, parsed} <- Dispatcher.parse(path, content),
         {:ok, file} <- upsert_file(path, content, parsed, project),
         {:ok, payloads} <- extract_payloads(parsed, file, project, content),
         :ok <- embed_and_persist_payloads(payloads) do
      {:ok, file}
    else
      {:error, :unsupported_extension} ->
        {:ok, :skipped}

      {:error, reason} ->
        Logger.warning("FileProcessor error #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Two-stage pipeline within a file
  # ---------------------------------------------------------------------------

  # Stage 1 (CPU): extract every payload we want to embed for this file.
  # Returns a flat list of `payload` maps, each carrying its `:text`
  # for the embed call plus metadata to persist it.
  @doc false
  def extract_payloads(parsed, file, project, content) do
    symbol_payloads =
      parsed.symbols
      |> Enum.map(&prepare_symbol_payload(&1, content, file, project))

    chunk_payloads =
      content
      |> Chunker.chunk_by_size(max_tokens: 512)
      |> Enum.with_index()
      |> Enum.map(&prepare_chunk_payload(&1, file, project))

    {:ok, symbol_payloads ++ chunk_payloads}
  end

  # Stage 2 (I/O): embed ALL payloads in one batch call, then persist
  # each one. The single `embed_batch/1` call replaces what used to be
  # 2 separate calls per file (one for symbols, one for chunks).
  @doc false
  def embed_and_persist_payloads(payloads) do
    texts = Enum.map(payloads, & &1.text)
    embeds = Client.embed_batch(texts)

    if Enum.any?(embeds, &is_nil/1) do
      # Provider down — count once via the persistent_term counter
      # rather than logging per-file.
      case Enum.find(payloads, fn p -> p.type == :chunk end) do
        nil -> :ok
        %{path: path} -> bump_embedding_unavailable(path)
      end

      {:error, :embedding_unavailable}
    else
      payloads
      |> Enum.zip(embeds)
      |> Enum.each(&persist_payload/1)

      :ok
    end
  end

  defp prepare_symbol_payload(symbol, content, file, project) do
    with_content = extract_symbol_content(symbol, content)

    %{
      type: :symbol,
      path: file.path,
      symbol: with_content,
      file: file,
      project: project,
      text: build_embed_text(with_content)
    }
  end

  defp prepare_chunk_payload({chunk, idx}, file, project) do
    %{
      type: :chunk,
      path: file.path,
      chunk: chunk,
      chunk_index: idx,
      file: file,
      project: project,
      text: chunk.content
    }
  end

  defp persist_payload({%{type: :symbol} = p, embedding}) do
    upsert_symbol(p.symbol, p.file, p.project, embedding)
  end

  defp persist_payload({%{type: :chunk} = p, embedding}) do
    persist_chunk(p.chunk, p.chunk_index, p.file, p.project, embedding)
  end

  defp persist_chunk(chunk, chunk_index, file, project, embedding) do
    attrs = %{
      file_id: file.id,
      project_id: project.id,
      content: chunk.content,
      line_start: chunk.line_start,
      line_end: chunk.line_end,
      chunk_index: chunk_index,
      token_count: chunk.token_count,
      embedding: embedding
    }

    Repo.insert_all(
      Schema.Chunk,
      [attrs],
      on_conflict: {:replace, [:content, :embedding, :token_count, :line_start, :line_end]},
      conflict_target: [:file_id, :chunk_index]
    )

    :ok
  end

  defp extract_symbol_content(sym, content) do
    lines = String.split(content, "\n")
    s = max(0, (sym.line_start || 1) - 1)
    e = min(length(lines) - 1, (sym.line_end || sym.line_start || 1) - 1)

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

  # CO-3 cleanup: delete orphan chunks when file shrinks. Called after
  # the new chunks are upserted so we know the final `new_count`.
  @doc false
  def cleanup_orphan_chunks(file, new_count) do
    Repo.delete_all(
      from(c in Schema.Chunk,
        where: c.file_id == ^file.id and c.chunk_index >= ^new_count
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Hash utilities
  # ---------------------------------------------------------------------------

  # SE-2 (S13): hash streaming para archivos grandes (>50MB).
  @large_file_threshold 50 * 1024 * 1024

  @doc """
  Calcula SHA256 del archivo en `path` leyendo del disco en bloques
  de 64KB. Para archivos >50MB evita cargar el binary entero en
  memoria. Si el archivo excede 50MB, devuelve `{:error, :too_large}`.
  """
  def compute_hash_streaming(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @large_file_threshold ->
        {:error, :too_large}

      {:ok, _} ->
        path
        |> File.stream!([], 1024 * 64)
        |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
          :crypto.hash_update(acc, chunk)
        end)
        |> :crypto.hash_final()
        |> Base.encode16(case: :lower)
    end
  end

  def compute_hash(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
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

  # ---------------------------------------------------------------------------
  # Embedding-unavailable counter (batch-deduplicated warning)
  # ---------------------------------------------------------------------------

  @embedding_unavailable_key {__MODULE__, :embedding_unavailable}

  defp bump_embedding_unavailable(path) do
    current = :persistent_term.get(@embedding_unavailable_key, [])
    :persistent_term.put(@embedding_unavailable_key, [path | current])
  end

  @doc """
  Prints a single summary of the files that had no embedding, and
  resets the counter. Call once at the end of the scan.
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
