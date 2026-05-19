defmodule Delfos.Parsers.TypescriptParser do
  @moduledoc """
  Extrae símbolos de archivos TypeScript/JavaScript.

  Reconoce: class, function, arrow functions exportadas, interface,
  type alias, enum y decoradores (@Component, @Injectable, etc.).
  """

  @todo_re ~r{//\s*(TODO|FIXME|HACK|XXX)\b.*}i

  def parse(path, content) do
    lines = String.split(content, "\n")

    %{
      symbols: extract_symbols(lines, path),
      docs: extract_jsdoc(content),
      todos: extract_todos(lines),
      line_count: length(lines)
    }
  end

  # ---------------------------------------------------------------------------
  # Extracción de símbolos
  # ---------------------------------------------------------------------------

  defp extract_symbols(lines, _path) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        # class (abstract o no, export o no)
        m = Regex.run(~r/(?:export\s+)?(?:abstract\s+)?class\s+(\w+)/, stripped) ->
          [build("class", Enum.at(m, 1), lineno, "public")]

        # function declaration
        m = Regex.run(~r/(?:export\s+)?(?:async\s+)?function\s+(\w+)/, stripped) ->
          visibility = if String.contains?(stripped, "export"), do: "public", else: "private"
          [build("function", Enum.at(m, 1), lineno, visibility)]

        # arrow function / exported const que es función
        m =
            Regex.run(
              ~r/export\s+(?:const|let)\s+(\w+)\s*=\s*(?:async\s+)?(?:\(|function)/,
              stripped
            ) ->
          [build("function", Enum.at(m, 1), lineno, "public")]

        # interface
        m = Regex.run(~r/(?:export\s+)?interface\s+(\w+)/, stripped) ->
          [build("interface", Enum.at(m, 1), lineno, "public")]

        # type alias
        m = Regex.run(~r/(?:export\s+)?type\s+(\w+)\s*=/, stripped) ->
          [build("type", Enum.at(m, 1), lineno, "public")]

        # enum
        m = Regex.run(~r/(?:export\s+)?(?:const\s+)?enum\s+(\w+)/, stripped) ->
          [build("enum", Enum.at(m, 1), lineno, "public")]

        # decorator (@Component, @Injectable, @NgModule, etc.)
        m = Regex.run(~r/^@(\w+)\s*[\(\{]?/, stripped) ->
          # los decoradores Angular/NestJS son metadata valiosa
          [build("decorator", Enum.at(m, 1), lineno, "public")]

        true ->
          []
      end
    end)
  end

  defp build(kind, name, lineno, visibility) do
    %{
      name: name,
      qualified_name: name,
      kind: kind,
      line_start: lineno,
      language: "typescript",
      visibility: visibility,
      metadata: %{}
    }
  end

  defp extract_jsdoc(content) do
    ~r|/\*\*(.*?)\*/|s
    |> Regex.scan(content)
    |> Enum.map(fn [_, doc] -> doc |> String.replace(~r/\s*\*\s*/, " ") |> String.trim() end)
    |> Enum.filter(&(String.length(&1) > 20))
  end

  defp extract_todos(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
