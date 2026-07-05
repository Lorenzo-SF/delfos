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
    Map.put(sym, :content, lines |> Enum.slice(s..e) |> Enum.join("\n"))
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
end
