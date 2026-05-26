defmodule Delfos.Parsers.TreeSitterParser do
  @moduledoc """
  Parser unificado basado en Tree-sitter.
  Extrae símbolos con rangos exactos, qualified_name con contexto,
  docs y TODOs. Compatible con :tree_sitter NIF.
  """
  @todo_re ~r{(?://|#|--|/\*|\*)\s*(TODO|FIXME|HACK|XXX|NOCOMMIT|BUG|DEBT)\b.*}i

  def parse(path, content) do
    lang = Delfos.Parsers.Dispatcher.language(path)
    grammar = load_grammar(lang)
    tree = TreeSitter.parse(grammar, content)
    query = load_query(lang)
    matches = TreeSitter.matches(tree, query)

    %{
      symbols: extract_symbols(matches, content, lang),
      docs: extract_docs(content, lang),
      todos: extract_todos(content),
      line_count: length(String.split(content, "\n"))
    }
  end

  defp load_grammar(lang) do
    case TreeSitter.load_grammar(lang) do
      {:ok, g} ->
        g

      {:error, :not_found} ->
        raise """
        Grammar no encontrado para #{lang}.
        Ejecuta: mix tree_sitter.install #{lang}
        """

      {:error, reason} ->
        raise "Error cargando grammar #{lang}: #{inspect(reason)}"
    end
  end

  defp load_query(lang) do
    path = Path.join([:code.priv_dir(:delfos), "queries", "#{lang}.scm"])

    case File.read(path) do
      {:ok, q} -> q
      _ -> fallback_query(lang)
    end
  end

  defp fallback_query("elixir"),
    do: "(call target: (identifier) @call_func) @call\n(identifier) @identifier"

  defp fallback_query("typescript"),
    do: "(function_declaration name: (identifier) @name) @function"

  defp fallback_query("python"), do: "(function_definition name: (identifier) @name) @function"
  defp fallback_query("dart"), do: "(class_definition name: (identifier) @name) @class"

  defp fallback_query("terraform"),
    do: "(block type: (identifier) @type label: (string) @name) @resource"

  defp fallback_query("config"), do: "(pair key: (flow_node) @name) @config"
  defp fallback_query(_), do: "(identifier) @identifier"

  defp extract_symbols(matches, content, lang) do
    line_offsets = build_line_offsets(content)
    context_stack = []

    symbols =
      Enum.reduce(matches, {[], context_stack}, fn {captures, _metadata}, {acc, stack} ->
        name =
          get_capture_text(captures, "name") || get_capture_text(captures, "func_name") ||
            get_capture_text(captures, "identifier")

        kind = map_capture_kind(captures)
        byte_start = get_capture_byte(captures, :start_byte)
        byte_end = get_capture_byte(captures, :end_byte) || byte_start

        stack = update_context_stack(stack, kind, name)
        qualified = build_qualified_name(stack, name)
        visibility = infer_visibility(kind, name, captures)

        line_start = byte_to_line(line_offsets, byte_start)
        line_end = byte_to_line(line_offsets, byte_end)

        body =
          if byte_start >= 0 and byte_end <= byte_size(content),
            do: String.slice(content, byte_start..byte_end),
            else: ""

        sym = %{
          name: name || "anonymous",
          qualified_name: qualified,
          kind: kind,
          line_start: line_start,
          line_end: line_end,
          visibility: visibility,
          language: lang,
          content: body,
          metadata: %{"stack" => stack}
        }

        {[sym | acc], stack}
      end)
      |> elem(0)
      |> Enum.reverse()

    Enum.reject(symbols, fn s -> s.name == "anonymous" and s.kind == "symbol" end)
  end

  defp build_line_offsets(content) do
    content
    |> String.split("\n", trim: false)
    |> Enum.reduce([], fn line, acc ->
      last = if acc == [], do: 0, else: List.last(acc) + String.length(line) + 1
      [last | acc]
    end)
    |> Enum.reverse()
  end

  defp byte_to_line(offsets, byte) do
    Enum.find_index(offsets, &(&1 > byte)) || length(offsets) - 1
  end

  defp get_capture_text(captures, tag) do
    case Enum.find(captures, fn {t, _} -> t == tag end) do
      {_, node} -> TreeSitter.node_text(node)
      nil -> nil
    end
  end

  defp get_capture_byte(captures, key) do
    case Enum.find(captures, fn {_, node} -> Map.has_key?(TreeSitter.node_range(node), key) end) do
      {_, node} -> TreeSitter.node_range(node)[key]
      nil -> nil
    end
  end

  defp map_capture_kind(captures) do
    Enum.reduce(captures, "symbol", fn {tag, _}, acc ->
      cond do
        tag in ["function", "function_declaration", "function_definition"] -> "function"
        tag in ["class", "class_declaration", "class_definition"] -> "class"
        tag in ["module", "defmodule"] -> "module"
        tag in ["macro", "defmacro"] -> "macro"
        tag in ["struct", "defstruct"] -> "struct"
        tag in ["type", "type_alias", "type_declaration"] -> "type"
        tag in ["interface", "interface_declaration"] -> "interface"
        tag in ["enum", "enum_declaration"] -> "enum"
        tag in ["decorator"] -> "decorator"
        tag in ["route", "route_declaration"] -> "route"
        tag in ["resource"] -> "resource"
        tag in ["config"] -> "config"
        true -> acc
      end
    end)
  end

  defp update_context_stack(stack, kind, name) do
    cond do
      kind in ["module", "class", "namespace"] ->
        [{kind, name} | stack]

      true ->
        stack
    end
  end

  defp build_qualified_name(stack, name) do
    parents = Enum.filter(stack, fn {k, _} -> k in ["module", "class", "namespace"] end)

    case parents do
      [] ->
        name || "unknown"

      list ->
        list
        |> Enum.reverse()
        |> Enum.map(fn {_, n} -> n end)
        |> Enum.join(".")
        |> Kernel.<>(".#{name || "unknown"}")
    end
  end

  defp infer_visibility(kind, name, captures) do
    cond do
      name && String.starts_with?(name, "_") -> "private"
      Enum.any?(captures, fn {tag, _} -> tag in ["private", "defp", "priv"] end) -> "private"
      true -> "public"
    end
  end

  defp extract_docs(content, lang) do
    case lang do
      "elixir" ->
        ~r/@(?:moduledoc|doc)\s+(?:~[SH]?)?"""([\s\S]*?)"""/s
        |> Regex.scan(content)
        |> Enum.map(fn [_, doc] -> String.trim(doc) end)

      "typescript" ->
        ~r|/\*\*([\s\S]*?)\*/|s
        |> Regex.scan(content)
        |> Enum.map(fn [_, doc] -> String.replace(doc, ~r/\s*\*\s?/m, "") |> String.trim() end)

      "python" ->
        ~r/"""([\s\S]*?)"""/s
        |> Regex.scan(content)
        |> Enum.map(fn [_, doc] -> String.trim(doc) end)

      "dart" ->
        ~r{///\s*(.*)}
        |> Regex.scan(content)
        |> Enum.map(fn [_, doc] -> String.trim(doc) end)

      _ ->
        []
    end
    |> Enum.filter(&(String.length(&1) > 20))
  end

  defp extract_todos(content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
