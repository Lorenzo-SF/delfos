defmodule Delfos.Indexer.Chunker do
  @moduledoc """
  Divide el contenido de un símbolo en chunks.
  Un chunk = una unidad semántica (función, clase).
  Si el símbolo supera max_chunk_tokens se divide con solapamiento.
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
          String.split(content, "\n") |> length(),
          0,
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
    # chars approx
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

  defp split_with_overlap(content, symbol_id, file_id, project_id) do
    lines = String.split(content, "\n")
    # ~40 chars/linea promedio
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

  defp chunk_by_size(text, chunk_size, stride) do
    chars = String.graphemes(text)
    total = length(chars)

    Stream.iterate(0, &(&1 + stride))
    |> Stream.take_while(&(&1 < total))
    |> Enum.map(fn start ->
      chunk = chars |> Enum.slice(start, chunk_size) |> Enum.join()
      line_start = text |> String.slice(0, start) |> String.split("\n") |> length()
      line_end = line_start + (String.split(chunk, "\n") |> length())
      {chunk, line_start, line_end}
    end)
  end

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
