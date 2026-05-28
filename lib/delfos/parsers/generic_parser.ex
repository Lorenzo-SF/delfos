defmodule Delfos.Parsers.GenericParser do
  @moduledoc """
  Parser genérico para lenguajes sin soporte específico (Rust, Go…).

  Extrae símbolos mediante patrones comunes:
  - Rust: fn, struct, enum, trait, impl, pub fn
  - Go:   func, type, struct, interface
  - Otros: funciones y clases con patrones habituales
  """

  @todo_re ~r{(?://|#)\s*(TODO|FIXME|HACK|XXX)\b.*}i

  def parse(path, content) do
    language = detect_language(path)
    lines = String.split(content, "\n")

    %{
      symbols: extract_symbols(lines, language),
      docs: [],
      todos: extract_todos(lines),
      line_count: length(lines)
    }
  end

  # ---------------------------------------------------------------------------
  # Detección de lenguaje
  # ---------------------------------------------------------------------------

  defp detect_language(path) do
    case Path.extname(path) do
      ".rs" -> "rust"
      ".go" -> "go"
      _ -> "unknown"
    end
  end

  # ---------------------------------------------------------------------------
  # Patrones por lenguaje
  # ---------------------------------------------------------------------------

  defp extract_symbols(lines, "rust") do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        m = Regex.run(~r/^(?:pub\s+)?(?:async\s+)?fn\s+(\w+)/, stripped) ->
          vis = if String.starts_with?(stripped, "pub"), do: "public", else: "private"
          [build("function", Enum.at(m, 1), lineno, "rust", vis)]

        m = Regex.run(~r/^(?:pub\s+)?struct\s+(\w+)/, stripped) ->
          [build("struct", Enum.at(m, 1), lineno, "rust", "public")]

        m = Regex.run(~r/^(?:pub\s+)?enum\s+(\w+)/, stripped) ->
          [build("enum", Enum.at(m, 1), lineno, "rust", "public")]

        m = Regex.run(~r/^(?:pub\s+)?trait\s+(\w+)/, stripped) ->
          [build("trait", Enum.at(m, 1), lineno, "rust", "public")]

        m = Regex.run(~r/^impl(?:<[^>]+>)?\s+([\w:]+)/, stripped) ->
          [build("impl", Enum.at(m, 1), lineno, "rust", "public")]

        true ->
          []
      end
    end)
  end

  defp extract_symbols(lines, "go") do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        m = Regex.run(~r/^func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)\s*\(/, stripped) ->
          vis = if String.match?(Enum.at(m, 1), ~r/^[A-Z]/), do: "public", else: "private"
          [build("function", Enum.at(m, 1), lineno, "go", vis)]

        m = Regex.run(~r/^type\s+(\w+)\s+struct/, stripped) ->
          [build("struct", Enum.at(m, 1), lineno, "go", "public")]

        m = Regex.run(~r/^type\s+(\w+)\s+interface/, stripped) ->
          [build("interface", Enum.at(m, 1), lineno, "go", "public")]

        m = Regex.run(~r/^type\s+(\w+)\s+/, stripped) ->
          [build("type", Enum.at(m, 1), lineno, "go", "public")]

        true ->
          []
      end
    end)
  end

  defp extract_symbols(lines, language) do
    # fallback genérico
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        m = Regex.run(~r/^(?:function|def|fn|func)\s+(\w+)/, stripped) ->
          [build("function", Enum.at(m, 1), lineno, language, "public")]

        m = Regex.run(~r/^(?:class|struct|type)\s+(\w+)/, stripped) ->
          [build("class", Enum.at(m, 1), lineno, language, "public")]

        true ->
          []
      end
    end)
  end

  defp build(kind, name, lineno, language, visibility) do
    %{
      name: name,
      qualified_name: name,
      kind: kind,
      line_start: lineno,
      language: language,
      visibility: visibility,
      metadata: %{}
    }
  end

  defp extract_todos(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
