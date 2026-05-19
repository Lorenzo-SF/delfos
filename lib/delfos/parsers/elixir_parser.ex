defmodule Delfos.Parsers.ElixirParser do
  @moduledoc "Extrae símbolos de archivos Elixir mediante análisis de texto."

  @todo_re ~r/#\s*(TODO|FIXME|HACK|XXX|NOCOMMIT|BUG|DEBT)\b.*/i
  @moduledoc_re ~r/@moduledoc\s+"""([\s\S]*?)"""/
  @doc_re ~r/@doc\s+"""([\s\S]*?)"""/

  def parse(path, content) do
    lines = String.split(content, "\n")
    symbols = extract_symbols(lines, path)
    docs = extract_docs(content)
    todos = extract_todos(lines)

    %{
      symbols: symbols,
      docs: docs,
      todos: todos,
      line_count: length(lines)
    }
  end

  defp extract_symbols(lines, path) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, []}, fn {line, lineno}, {acc, current_module, pending_doc} ->
      stripped = String.trim(line)

      cond do
        match = Regex.run(~r/^defmodule\s+([\w.]+)/, stripped) ->
          sym =
            build_symbol("module", Enum.at(match, 1), lineno, path, current_module, pending_doc)

          {[sym | acc], Enum.at(match, 1), []}

        match = Regex.run(~r/^def\s+(\w+)/, stripped) ->
          sym =
            build_symbol("function", Enum.at(match, 1), lineno, path, current_module, pending_doc)

          {[sym | acc], current_module, []}

        match = Regex.run(~r/^defp\s+(\w+)/, stripped) ->
          sym =
            build_symbol(
              "function",
              Enum.at(match, 1),
              lineno,
              path,
              current_module,
              pending_doc,
              "private"
            )

          {[sym | acc], current_module, []}

        match = Regex.run(~r/^@callback\s+(\w+)/, stripped) ->
          sym =
            build_symbol(
              "constant",
              "@callback/#{Enum.at(match, 1)}",
              lineno,
              path,
              current_module,
              []
            )

          {[sym | acc], current_module, []}

        String.starts_with?(stripped, "@doc") ->
          {acc, current_module, [stripped]}

        true ->
          {acc, current_module, []}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp build_symbol(kind, name, lineno, _path, module, doc, visibility \\ "public") do
    qualified = if module, do: "#{module}.#{name}", else: name

    %{
      name: name,
      qualified_name: qualified,
      kind: kind,
      visibility: visibility,
      line_start: lineno,
      language: "elixir",
      docstring: List.first(doc),
      metadata: %{module: module}
    }
  end

  defp extract_docs(content) do
    moduledocs = Regex.scan(@moduledoc_re, content) |> Enum.map(&Enum.at(&1, 1))
    docs = Regex.scan(@doc_re, content) |> Enum.map(&Enum.at(&1, 1))
    (moduledocs ++ docs) |> Enum.reject(&is_nil/1) |> Enum.map(&String.trim/1)
  end

  defp extract_todos(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
