defmodule Delfos.Parsers.TypescriptParser do
  @moduledoc """
    Extrae símbolos de archivos TypeScript/JavaScript.
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

  defp extract_symbols(lines, _path) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        m = Regex.run(~r/(?:export\s+)?(?:abstract\s+)?class\s+(\w+)/, stripped) ->
          [
            %{
              name: Enum.at(m, 1),
              kind: "class",
              line_start: lineno,
              language: "typescript",
              visibility: "public"
            }
          ]

        m = Regex.run(~r/(?:export\s+)?(?:async\s+)?function\s+(\w+)/, stripped) ->
          [
            %{
              name: Enum.at(m, 1),
              kind: "function",
              line_start: lineno,
              language: "typescript",
              visibility: "public"
            }
          ]

        m =
            Regex.run(
              ~r/export\s+(?:const|let)\s+(\w+)\s*=\s*(?:async\s+)?(?:\(|function)/,
              stripped
            ) ->
          [
            %{
              name: Enum.at(m, 1),
              kind: "function",
              line_start: lineno,
              language: "typescript",
              visibility: "public"
            }
          ]

        m = Regex.run(~r/(?:export\s+)?interface\s+(\w+)/, stripped) ->
          [
            %{
              name: Enum.at(m, 1),
              kind: "constant",
              line_start: lineno,
              language: "typescript",
              visibility: "public",
              metadata: %{subkind: "interface"}
            }
          ]

        true ->
          []
      end
    end)
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
