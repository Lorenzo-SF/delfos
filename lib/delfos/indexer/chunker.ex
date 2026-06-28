defmodule Delfos.Indexer.Chunker do
  @moduledoc """
  Divide el contenido de un símbolo en chunks semánticos.

  Un chunk = una unidad semántica (función, clase).
  Si el símbolo supera max_chunk_tokens se divide con solapamiento.

  Mejora de rendimiento: `chunk_by_size` usa `:binary.part/3` en lugar de
  `String.graphemes/1`, evitando la conversión a lista de grafemas que era
  O(n) en memoria para archivos grandes.
  """

  @max_tokens Application.compile_env(:delfos, [:indexing, :max_chunk_tokens], 512)
  @overlap_tokens 64

  def chunk_symbol(content, symbol_id, file_id, project_id) do
    tokens_approx = estimate_tokens(content)

    if tokens_approx <= @max_tokens do
      [
        build_chunk(
          content,
          0,
          0,
          content |> String.split("\n") |> length(),
          tokens_approx,
          symbol_id,
          file_id,
          project_id
        )
      ]
    else
      split_with_overlap(content, symbol_id, file_id, project_id)
    end
  end

  def chunk_file(content, file_id, project_id) do
    chunk_size = @max_tokens * 4
    stride = (@max_tokens - @overlap_tokens) * 4

    content
    |> chunk_by_size(chunk_size, stride)
    |> Enum.with_index()
    |> Enum.map(fn {{text, line_start, line_end}, idx} ->
      build_chunk(
        text,
        idx,
        line_start,
        line_end,
        estimate_tokens(text),
        nil,
        file_id,
        project_id
      )
    end)
  end

  # ---------------------------------------------------------------------------
  # División con solapamiento (por líneas)
  # ---------------------------------------------------------------------------

  defp split_with_overlap(content, symbol_id, file_id, project_id) do
    lines = String.split(content, "\n")
    # ~40 chars/línea promedio
    chunk_lines = (@max_tokens * 4) |> div(40)
    stride = max(chunk_lines - 10, 5)

    lines
    |> Enum.chunk_every(chunk_lines, stride, :discard)
    |> Enum.with_index()
    |> Enum.map(fn {chunk_lines_list, idx} ->
      text = Enum.join(chunk_lines_list, "\n")

      build_chunk(
        text,
        idx,
        idx * stride + 1,
        idx * stride + length(chunk_lines_list),
        estimate_tokens(text),
        symbol_id,
        file_id,
        project_id
      )
    end)
  end

  @doc """
  Divide contenido por tamaño de tokens con opciones.

  Opciones:
    - `:max_tokens` — número máximo de tokens por chunk (default: 512)
    - `:overlap` — solapamiento entre chunks (default: 64)
  """
  def chunk_by_size(content, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, @max_tokens)
    overlap = Keyword.get(opts, :overlap, @overlap_tokens)

    chunk_by_size(content, max_tokens, overlap)
  end

  # ---------------------------------------------------------------------------
  # División binaria eficiente (para chunk_file)
  # ---------------------------------------------------------------------------

  defp chunk_by_size(text, chunk_size, stride) do
    byte_size_text = byte_size(text)

    Stream.iterate(0, &(&1 + stride))
    |> Stream.take_while(&(&1 < byte_size_text))
    |> Enum.map(fn start ->
      # Usar :binary.part para evitar convertir a lista de grafemas
      actual_chunk_size = min(chunk_size, byte_size_text - start)
      chunk = :binary.part(text, start, actual_chunk_size)

      # Ajustar al límite de carácter UTF-8 válido más cercano
      chunk = ensure_valid_utf8(chunk)

      prefix = :binary.part(text, 0, start)
      line_start = prefix |> String.split("\n") |> length()
      line_end = line_start + (chunk |> String.split("\n") |> length())

      {chunk, line_start, line_end}
    end)
  end

  # Recorta el final del binario hasta encontrar un byte de inicio de carácter UTF-8 válido
  defp ensure_valid_utf8(binary) do
    case String.valid?(binary) do
      true ->
        binary

      false ->
        # Retroceder byte a byte hasta UTF-8 válido (máximo 3 bytes)
        do_trim_utf8(binary, byte_size(binary) - 1, 3)
    end
  end

  defp do_trim_utf8(_binary, _pos, 0), do: ""

  defp do_trim_utf8(binary, pos, retries) when pos >= 0 do
    trimmed = :binary.part(binary, 0, pos)

    if String.valid?(trimmed) do
      trimmed
    else
      do_trim_utf8(binary, pos - 1, retries - 1)
    end
  end

  defp do_trim_utf8(_binary, _pos, _retries), do: ""

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_chunk(
         content,
         idx,
         line_start,
         line_end,
         token_count,
         symbol_id,
         file_id,
         project_id
       ) do
    %{
      content: content,
      chunk_index: idx,
      line_start: line_start,
      line_end: line_end,
      token_count: token_count,
      symbol_id: symbol_id,
      file_id: file_id,
      project_id: project_id
    }
  end

  defp estimate_tokens(text), do: div(String.length(text), 4)
end
