defmodule Delfos.Indexer.FileProcessor do
  @moduledoc """
  Procesa un archivo individual: parseo, persistencia y embedding.

  Mejoras respecto a la versión anterior:
  - Los embeddings de símbolos se generan en batch (un solo roundtrip HTTP).
  - El texto embebido incluye kind, qualified_name, docstring y @spec para
    mejorar la búsqueda semántica con queries en lenguaje natural.
  - `find_line_end` usa indentación y el nesting de `end` para delimitar
    correctamente los cuerpos de funciones y módulos.
  - El hash del archivo se calcula una sola vez y se reutiliza.
  """

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
      hash = compute_hash(content)
      stat = File.stat!(abs_path)

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

      Repo.delete_all(from(s in Schema.Symbol, where: s.file_id == ^file.id))
      Repo.delete_all(from(c in Schema.Chunk, where: c.file_id == ^file.id))

      symbols = insert_symbols(parsed.symbols, file, project, content)
      insert_chunks(symbols, file, project)

      Logger.debug("Procesado: #{relative} (#{length(symbols)} símbolos)")
      {:ok, file}
    else
      {:error, reason} ->
        Logger.warning("Error procesando #{relative}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Hash
  # ---------------------------------------------------------------------------

  def compute_hash(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  # ---------------------------------------------------------------------------
  # Símbolos — embeddings en batch
  # ---------------------------------------------------------------------------

  defp insert_symbols(raw_symbols, file, project, full_content) do
    full_lines = String.split(full_content, "\n")

    # Tree-sitter ya devuelve line_start y line_end exactos (0-indexed)
    enriched =
      Enum.map(raw_symbols, fn sym ->
        start_line = max(sym.line_start - 1, 0)
        end_line = min(sym.line_end - 1, length(full_lines) - 1)
        content = Enum.slice(full_lines, start_line..end_line) |> Enum.join("\n")

        Map.merge(sym, %{
          line_start: sym.line_start,
          line_end: sym.line_end,
          content: content,
          language: file.language
        })
      end)

    embed_texts = Enum.map(enriched, &build_embed_text/1)
    embeddings = Client.embed_batch(embed_texts)

    Enum.zip(enriched, embeddings)
    |> Enum.map(fn {sym, embedding} ->
      attrs =
        Map.merge(sym, %{
          file_id: file.id,
          project_id: project.id,
          embedding: embedding,
          qualified_name: sym.qualified_name || sym.name
        })

      Repo.insert!(Schema.Symbol.changeset(%Schema.Symbol{}, attrs), returning: true)
    end)
  end

  @doc """
  Construye el texto a embeber para un símbolo.
  Incluye kind, nombre calificado, docstring y @spec para que la búsqueda
  semántica funcione bien con preguntas en lenguaje natural.
  """
  def build_embed_text(sym) do
    parts =
      [
        "#{sym[:kind]} #{sym[:qualified_name] || sym[:name]}",
        sym[:docstring],
        sym[:signature],
        sym[:content]
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    parts |> Enum.join("\n") |> String.slice(0, 4000)
  end

  # ---------------------------------------------------------------------------
  # Chunks
  # ---------------------------------------------------------------------------

  defp insert_chunks(symbols, file, project) do
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

  # ---------------------------------------------------------------------------
  # find_line_end — basado en nesting de `end` e indentación
  # ---------------------------------------------------------------------------

  @doc """
  Determina la línea final de un símbolo.

  Estrategia:
  - Para Elixir: cuenta el nesting de bloques (do/end) y cierra cuando
    el contador vuelve a cero. Esto evita cortar en el primer `end` interno.
  - Para otros lenguajes: busca la siguiente definición al mismo nivel de
    indentación como heurístico.
  - Límite máximo de 300 líneas para evitar símbolos infinitos.
  """
  def find_line_end(lines, line_start, kind \\ nil) do
    start_idx = max(line_start - 1, 0)
    start_line = Enum.at(lines, start_idx, "")
    base_indent = indent_level(start_line)
    max_scan = 300

    slice = Enum.slice(lines, start_idx + 1, max_scan)

    # Para módulos y funciones Elixir usamos conteo de bloques do/end
    use_nesting = kind in ["module", "function", "macro", nil]

    if use_nesting do
      find_end_by_nesting(slice, line_start, base_indent)
    else
      find_end_by_indent(slice, line_start, base_indent)
    end
  end

  defp find_end_by_nesting(lines, line_start, _base_indent) do
    # Arrancamos con depth=1 porque ya estamos dentro del bloque
    lines
    |> Enum.with_index(line_start + 1)
    |> Enum.reduce_while(1, fn {line, lineno}, depth ->
      stripped = String.trim(line)
      opens = count_opens(stripped)
      closes = count_closes(stripped)
      new_depth = depth + opens - closes

      if new_depth <= 0 do
        {:halt, lineno}
      else
        {:cont, new_depth}
      end
    end)
    |> then(fn
      result when is_integer(result) -> result
      # no encontró end — límite
      _ -> line_start + 300
    end)
  end

  defp find_end_by_indent(lines, line_start, base_indent) do
    lines
    |> Enum.with_index(line_start + 1)
    |> Enum.find(fn {line, _} ->
      stripped = String.trim(line)
      not_blank = stripped != ""
      same_or_less = indent_level(line) <= base_indent

      not_blank and same_or_less and
        (String.starts_with?(stripped, "def ") or
           String.starts_with?(stripped, "defp ") or
           String.starts_with?(stripped, "defmodule ") or
           String.starts_with?(stripped, "class ") or
           String.starts_with?(stripped, "func ") or
           String.starts_with?(stripped, "fn ") or
           String.starts_with?(stripped, "pub fn"))
    end)
    |> case do
      {_, lineno} -> lineno - 1
      nil -> line_start + 300
    end
  end

  # Palabras que abren un bloque en Elixir
  @open_keywords ~w(do fn with if unless case cond try receive quote)
  defp count_opens(line) do
    keyword_opens =
      @open_keywords
      |> Enum.count(fn kw ->
        String.contains?(line, " #{kw} ") or String.ends_with?(line, " #{kw}") or line == kw
      end)

    inline_do = if String.contains?(line, ", do:"), do: 1, else: 0
    keyword_opens + inline_do
  end

  defp count_closes(line) do
    line
    |> String.split(~r/\bend\b/)
    |> length()
    |> Kernel.-(1)
  end

  defp indent_level(line) do
    line
    |> String.length()
    |> Kernel.-(String.length(String.trim_leading(line)))
  end

  defp extract_content(lines, start, stop) do
    lines
    |> Enum.slice(max(start - 1, 0), max(stop - start + 1, 1))
    |> Enum.join("\n")
  end
end
