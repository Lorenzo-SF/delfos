defmodule Delfos.Parsers.PythonParser do
  @moduledoc "Extrae símbolos de archivos Python."

  def parse(_path, content) do
    lines = String.split(content, "\n")

    %{
      symbols: extract_symbols(lines),
      docs: extract_docstrings(content),
      todos: extract_todos(lines),
      line_count: length(lines)
    }
  end

  defp extract_symbols(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        m = Regex.run(~r/^(?:async\s+)?def\s+(\w+)/, stripped) ->
          [%{name: Enum.at(m, 1), kind: "function", line_start: lineno, language: "python"}]

        m = Regex.run(~r/^class\s+(\w+)/, stripped) ->
          [%{name: Enum.at(m, 1), kind: "class", line_start: lineno, language: "python"}]

        true ->
          []
      end
    end)
  end

  defp extract_docstrings(content) do
    ~r/"""(.*?)"""/s
    |> Regex.scan(content)
    |> Enum.map(fn [_, doc] -> String.trim(doc) end)
    |> Enum.filter(&(String.length(&1) > 20))
  end

  defp extract_todos(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(~r/#\s*(TODO|FIXME|HACK)/i, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
