defmodule Delfos.Parsers.PythonParser do
  @moduledoc """
  Extrae símbolos de archivos Python.

  Reconoce: def, async def, class, decoradores (@dataclass, @staticmethod, etc.)
  y detecta visibilidad por convención de nombres (_ prefix).
  """

  @todo_re ~r/#\s*(TODO|FIXME|HACK|XXX)\b.*/i

  def parse(_path, content) do
    lines = String.split(content, "\n")

    %{
      symbols: extract_symbols(lines),
      docs: extract_docstrings(content),
      todos: extract_todos(lines),
      line_count: length(lines)
    }
  end

  # ---------------------------------------------------------------------------
  # Extracción de símbolos
  # ---------------------------------------------------------------------------

  defp extract_symbols(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        # función / método (sync o async)
        m = Regex.run(~r/^(?:async\s+)?def\s+(\w+)\s*\(/, stripped) ->
          name = Enum.at(m, 1)
          visibility = if String.starts_with?(name, "_"), do: "private", else: "public"
          [%{name: name, qualified_name: name, kind: "function", line_start: lineno, language: "python", visibility: visibility, metadata: %{}}]

        # class (con o sin herencia)
        m = Regex.run(~r/^class\s+(\w+)[\s:(]/, stripped) ->
          [%{name: Enum.at(m, 1), qualified_name: Enum.at(m, 1), kind: "class", line_start: lineno, language: "python", visibility: "public", metadata: %{}}]

        # decorador (metadata valiosa: @dataclass, @property, @staticmethod, @app.route…)
        m = Regex.run(~r/^@([\w.]+)/, stripped) ->
          [%{name: Enum.at(m, 1), qualified_name: Enum.at(m, 1), kind: "decorator", line_start: lineno, language: "python", visibility: "public", metadata: %{}}]

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
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
