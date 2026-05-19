defmodule Delfos.Indexer.FileProcessor do
  @moduledoc "Procesa un archivo individual: parseo, persistencia y embedding."
  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}
  alias Delfos.Parsers.Dispatcher
  alias Delfos.Indexer.Chunker
  alias Delfos.LLM.Client

  def process(abs_path, project) do
    relative = Path.relative_to(abs_path, project.path)
    language = Dispatcher.language(abs_path)

    with {:ok, content} <- File.read(abs_path),
         {:ok, parsed} <- Dispatcher.parse(abs_path, content) do
      hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      stat = File.stat!(abs_path)

      # Upsert del archivo
      file_attrs = %{
        path: relative,
        language: language,
        size_bytes: stat.size,
        line_count: parsed.line_count,
        last_modified: stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC"),
        last_indexed: DateTime.utc_now(),
        content_hash: hash,
        project_id: project.id
      }

      file =
        case Repo.get_by(Schema.File, project_id: project.id, path: relative) do
          nil -> Repo.insert!(Schema.File.changeset(%Schema.File{}, file_attrs))
          existing -> Repo.update!(Schema.File.changeset(existing, file_attrs))
        end

      # Borrar símbolos y chunks anteriores (van a regenerarse)
      Repo.delete_all(from(s in Schema.Symbol, where: s.file_id == ^file.id))
      Repo.delete_all(from(c in Schema.Chunk, where: c.file_id == ^file.id))

      # Insertar símbolos nuevos
      symbols = insert_symbols(parsed.symbols, file, project, content)

      # Generar y insertar chunks con embeddings
      insert_chunks(symbols, file, project, content)

      Logger.debug("Procesado: #{relative} (#{length(symbols)} símbolos)")
      {:ok, file}
    else
      {:error, reason} ->
        Logger.warning("Error procesando #{relative}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp insert_symbols(raw_symbols, file, project, full_content) do
    full_lines = String.split(full_content, "\n")

    Enum.map(raw_symbols, fn sym ->
      line_end = find_line_end(full_lines, sym.line_start)
      content = extract_content(full_lines, sym.line_start, line_end)

      embedding =
        case Client.embed(content) do
          {:ok, vec} -> vec
          _ -> nil
        end

      attrs =
        Map.merge(sym, %{
          file_id: file.id,
          project_id: project.id,
          line_end: line_end,
          content: content,
          embedding: embedding,
          qualified_name: sym[:qualified_name] || sym[:name]
        })

      Repo.insert!(Schema.Symbol.changeset(%Schema.Symbol{}, attrs), returning: true)
    end)
  end

  defp insert_chunks(symbols, file, project, _full_content) do
    Enum.each(symbols, fn symbol ->
      chunks = Chunker.chunk_symbol(symbol.content || "", symbol.id, file.id, project.id)

      texts = Enum.map(chunks, & &1.content)
      embeddings = Client.embed_batch(texts)

      chunks
      |> Enum.zip(embeddings)
      |> Enum.each(fn {chunk_attrs, embedding} ->
        attrs = Map.put(chunk_attrs, :embedding, embedding)
        Repo.insert!(Schema.Chunk.changeset(%Schema.Chunk{}, attrs))
      end)
    end)
  end

  defp find_line_end(lines, line_start) do
    # Heurístico: busca el siguiente símbolo de nivel similar
    end_line =
      Enum.slice(lines, line_start, 200)
      |> Enum.with_index(line_start + 1)
      |> Enum.find(fn {line, _} ->
        stripped = String.trim(line)

        String.starts_with?(stripped, "def ") or
          String.starts_with?(stripped, "defp ") or
          String.starts_with?(stripped, "defmodule ") or
          String.starts_with?(stripped, "end")
      end)

    case end_line do
      {_, no} -> no
      nil -> line_start + 50
    end
  end

  defp extract_content(lines, start, stop) do
    lines
    |> Enum.slice(max(start - 1, 0), max(stop - start + 1, 1))
    |> Enum.join("\n")
  end
end
