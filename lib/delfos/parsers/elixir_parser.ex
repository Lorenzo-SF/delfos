defmodule Delfos.Parsers.ElixirParser do
  @moduledoc """
  Extrae símbolos de archivos Elixir mediante análisis de texto.

  Reconoce: defmodule, def, defp, defmacro, defmacrop, defstruct,
  @type, @typep, @opaque, @callback, @spec, use, @behaviour.
  """

  @todo_re ~r/#\s*(TODO|FIXME|HACK|XXX|NOCOMMIT|BUG|DEBT)\b.*/i
  # lib/delfos/parsers/elixir_parser.ex (reemplaza las dos líneas actuales)
  @doc_re ~r/@(?:moduledoc|doc)\s+(?:~[SH]?)?"""([\s\S]*?)"""/s
  @doc_re ~r/@doc\s+"""([\s\S]*?)"""/s

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

  # ---------------------------------------------------------------------------
  # Extracción de símbolos
  # ---------------------------------------------------------------------------

  defp extract_symbols(lines, path) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, [], []}, fn {line, lineno},
                                         {acc, current_module, pending_doc, pending_spec} ->
      stripped = String.trim(line)

      cond do
        # defmodule
        match = Regex.run(~r/^defmodule\s+([\w.]+)/, stripped) ->
          sym = build_symbol("module", Enum.at(match, 1), lineno, path, nil, pending_doc)
          {[sym | acc], Enum.at(match, 1), [], []}

        # def público
        match = Regex.run(~r/^def\s+(\w+)/, stripped) ->
          sym =
            build_symbol(
              "function",
              Enum.at(match, 1),
              lineno,
              path,
              current_module,
              pending_doc,
              "public",
              pending_spec
            )

          {[sym | acc], current_module, [], []}

        # def privado
        match = Regex.run(~r/^defp\s+(\w+)/, stripped) ->
          sym =
            build_symbol(
              "function",
              Enum.at(match, 1),
              lineno,
              path,
              current_module,
              pending_doc,
              "private",
              pending_spec
            )

          {[sym | acc], current_module, [], []}

        # defmacro público
        match = Regex.run(~r/^defmacro\s+(\w+)/, stripped) ->
          sym =
            build_symbol(
              "macro",
              Enum.at(match, 1),
              lineno,
              path,
              current_module,
              pending_doc,
              "public",
              pending_spec
            )

          {[sym | acc], current_module, [], []}

        # defmacro privado
        match = Regex.run(~r/^defmacrop\s+(\w+)/, stripped) ->
          sym =
            build_symbol(
              "macro",
              Enum.at(match, 1),
              lineno,
              path,
              current_module,
              pending_doc,
              "private",
              pending_spec
            )

          {[sym | acc], current_module, [], []}

        # defstruct
        match = Regex.run(~r/^defstruct\s+(.+)/, stripped) ->
          sym =
            build_symbol(
              "struct",
              current_module || "AnonymousStruct",
              lineno,
              path,
              current_module,
              pending_doc,
              "public",
              []
            )
            |> Map.put(:metadata, %{module: current_module, fields_raw: Enum.at(match, 1)})

          {[sym | acc], current_module, [], []}

        # @type / @typep / @opaque
        match = Regex.run(~r/^@(type|typep|opaque)\s+(\w+)/, stripped) ->
          visibility = if Enum.at(match, 1) == "typep", do: "private", else: "public"

          sym =
            build_symbol(
              "type",
              Enum.at(match, 2),
              lineno,
              path,
              current_module,
              [],
              visibility,
              []
            )

          {[sym | acc], current_module, [], []}

        # @callback
        match = Regex.run(~r/^@callback\s+(\w+)/, stripped) ->
          sym =
            build_symbol(
              "callback",
              Enum.at(match, 1),
              lineno,
              path,
              current_module,
              [],
              "public",
              []
            )

          {[sym | acc], current_module, [], []}

        # @spec — acumular para el siguiente def
        Regex.match?(~r/^@spec\s+/, stripped) ->
          {acc, current_module, pending_doc, [stripped | pending_spec]}

        # @doc — acumular
        String.starts_with?(stripped, "@doc") ->
          {acc, current_module, [stripped], pending_spec}

        # use SomeModule — registrar como dependencia semántica
        match = Regex.run(~r/^use\s+([\w.]+)/, stripped) ->
          sym =
            build_symbol("use", Enum.at(match, 1), lineno, path, current_module, [], "public", [])

          {[sym | acc], current_module, [], []}

        # @behaviour
        match = Regex.run(~r/^@behaviour\s+([\w.]+)/, stripped) ->
          sym =
            build_symbol(
              "behaviour",
              Enum.at(match, 1),
              lineno,
              path,
              current_module,
              [],
              "public",
              []
            )

          {[sym | acc], current_module, [], []}

        true ->
          {acc, current_module, [], pending_spec}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp build_symbol(kind, name, lineno, _path, module, doc, visibility \\ "public", specs \\ []) do
    qualified =
      if module && kind not in ["module", "use", "behaviour"], do: "#{module}.#{name}", else: name

    %{
      name: name,
      qualified_name: qualified,
      kind: kind,
      visibility: visibility,
      line_start: lineno,
      language: "elixir",
      docstring: List.first(doc),
      signature: List.first(specs),
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
