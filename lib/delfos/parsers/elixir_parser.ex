defmodule Delfos.Parsers.ElixirParser do
  @moduledoc """
  Extrae símbolos de archivos Elixir mediante análisis del AST.

  CO-1: usa `Code.string_to_quoted!/1` en lugar de regex. Esto
  resuelve C1 (nested `defmodule`), C3 (captura `line_end`), C6
  (heredocs ya no confunden al tokenizer), y elimina el límite de
  `defmodule Foo.Bar.Baz` que solo capturaba el primer segmento.

  Reconoce: defmodule, def, defp, defmacro, defmacrop, defstruct,
  @type, @typep, @opaque, @callback, @spec, use, @behaviour.
  """

  @todo_re ~r/#\s*(TODO|FIXME|HACK|XXX|NOCOMMIT|BUG|DEBT)\b.*/i

  # API pública — sin cambios. Devuelve el mismo shape que antes:
  #   %{symbols: [...], docs: [...], todos: [...], line_count: N}
  # Más un campo opcional `:line_end` en cada símbolo (C3).
  def parse(path, content) do
    lines = String.split(content, "\n")

    case Code.string_to_quoted(content, columns: true, line: 1) do
      {:ok, ast} ->
        docs_per_line = extract_docs_per_line(lines)
        specs_per_line = extract_specs_per_line(lines)

        # Macro.prewalk con un acc que crece: el closure recibe cada nodo
        # (en pre-order: padres antes que hijos) y el acc actual. Devolvemos
        # `{node, [node | acc]}` para acumular todos los visitados.
        symbols =
          ast
          |> Macro.prewalk([], fn node, acc -> {node, [node | acc]} end)
          |> elem(1)
          |> Enum.flat_map(&extract_top_level(&1, docs_per_line, specs_per_line, path))

        %{
          symbols: symbols,
          docs: collect_doc_strings(docs_per_line),
          todos: extract_todos(lines),
          line_count: length(lines)
        }

      {:error, _parse_err} ->
        # Código con errores de sintaxis — devolvemos estructura vacía
        # en lugar de explotar. El file_processor acepta esto (skipped).
        %{
          symbols: [],
          docs: [],
          todos: extract_todos(lines),
          line_count: length(lines)
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Extracción top-level
  # ---------------------------------------------------------------------------

  # Procesa un nodo del AST. Devuelve una lista de símbolos (0, 1 o más).
  # Los nested `defmodule` se manejan porque cada uno aparece como
  # un {:defmodule, ...} en algún nivel del árbol (el walker los visita).
  defp extract_top_level({:defmodule, meta, [aliases, [do: block]]}, docs, specs, path) do
    module_name = aliases_to_string(aliases)
    line_start = meta[:line] || 1
    line_end = meta_to_line_end(meta, path)
    doc = find_annotation_above(docs, line_start)

    module_sym =
      build_symbol("module", module_name, line_start, line_end, path, nil, "public", doc, nil)

    # Hijos: cualquier def/defp/etc dentro del bloque del module.
    children = extract_from_block(block, module_name, docs, specs, path)
    [module_sym | children]
  end

  defp extract_top_level({:use, meta, [aliases]}, _docs, _specs, path) do
    line = meta[:line] || 1

    [
      build_symbol(
        "use",
        aliases_to_string(aliases),
        line,
        meta_to_line_end(meta, path),
        path,
        nil,
        "public",
        nil,
        nil
      )
    ]
  end

  defp extract_top_level({:@, meta, [{:behaviour, _, [aliases]}]}, _docs, _specs, path) do
    line = meta[:line] || 1

    [
      build_symbol(
        "behaviour",
        aliases_to_string(aliases),
        line,
        meta_to_line_end(meta, path),
        path,
        nil,
        "public",
        nil,
        nil
      )
    ]
  end

  # Cualquier otra cosa en top-level: ignorar (alias, import, attr, etc.)
  defp extract_top_level(_node, _docs, _specs, _path), do: []

  # ---------------------------------------------------------------------------
  # Extracción desde el cuerpo de un defmodule
  # ---------------------------------------------------------------------------

  # El bloque `do:` puede ser `{:__block__, _, stmts}` (varias stmts)
  # o una sola statement directa. En ambos casos iteramos y aplicamos
  # `extract_in_module/5` (que busca def/defp/defmacro/etc, NO top-level).
  defp extract_from_block({:__block__, _, stmts}, module, docs, specs, path) do
    Enum.flat_map(stmts, &extract_in_module(&1, module, docs, specs, path))
  end

  defp extract_from_block(ast, module, docs, specs, path) when is_list(ast) do
    Enum.flat_map(ast, &extract_in_module(&1, module, docs, specs, path))
  end

  defp extract_from_block(node, module, docs, specs, path) do
    extract_in_module(node, module, docs, specs, path)
  end

  # ---------------------------------------------------------------------------
  # Extracción DENTRO de un defmodule (def, defp, defmacro, defstruct, @type, @callback)
  # ---------------------------------------------------------------------------

  # Patrón: `def name(args), do: body` o `def name(args) do ... end`
  # AST: {:def, meta, [{:name, _, args} | guards], [do: body]}
  defp extract_in_module({kind, meta, args_ast}, module, docs, specs, path)
       when kind in [:def, :defp, :defmacro, :defmacrop] do
    line_start = meta[:line] || 1
    line_end = meta_to_line_end(meta, path)
    visibility = if kind in [:defp, :defmacrop], do: "private", else: "public"
    kind_str = if kind in [:defmacro, :defmacrop], do: "macro", else: "function"

    name = infer_def_name(args_ast)

    if name do
      doc = find_annotation_above(docs, line_start)
      spec = find_annotation_above(specs, line_start)

      [
        build_symbol(
          kind_str,
          name,
          line_start,
          line_end,
          path,
          module,
          visibility,
          doc,
          spec
        )
      ]
    else
      []
    end
  end

  # `defstruct` — AST: {:defstruct, meta, [fields]} o {:defstruct, meta, [fields, [do: ...]]}
  defp extract_in_module({:defstruct, meta, _fields}, module, docs, _specs, path) do
    line_start = meta[:line] || 1
    line_end = meta_to_line_end(meta, path)
    doc = find_annotation_above(docs, line_start)
    name = module || "AnonymousStruct"

    [
      build_symbol(
        "struct",
        name,
        line_start,
        line_end,
        path,
        module,
        "public",
        doc,
        nil
      )
    ]
  end

  # `@type` / `@typep` / `@opaque` — AST: {:@, meta, [{kind, _, [{:name, _, []}]}]}
  defp extract_in_module({:@, meta, [{kind, _, [{:name, _, [name_ast]}]}]}, module, _docs, _specs, path)
       when kind in [:type, :typep, :opaque] do
    line_start = meta[:line] || 1
    line_end = meta_to_line_end(meta, path)
    visibility = if kind == :typep, do: "private", else: "public"

    [
      build_symbol(
        "type",
        atom_or_string(name_ast),
        line_start,
        line_end,
        path,
        module,
        visibility,
        nil,
        nil
      )
    ]
  end

  # `@callback` — AST: {:@, meta, [{:callback, _, [{:name, _, _}]}]}
  defp extract_in_module({:@, meta, [{:callback, _, [{:name, _, [name_ast]}]}]}, module, _docs, _specs, path) do
    line_start = meta[:line] || 1
    line_end = meta_to_line_end(meta, path)

    [
      build_symbol(
        "callback",
        atom_or_string(name_ast),
        line_start,
        line_end,
        path,
        module,
        "public",
        nil,
        nil
      )
    ]
  end

  # Si hay un `defmodule` anidado dentro de otro, lo extraemos también.
  defp extract_in_module({:defmodule, _meta, _} = node, _outer_module, docs, specs, path) do
    extract_top_level(node, docs, specs, path)
  end

  # Cualquier otro nodo dentro de un módulo: ignorar.
  defp extract_in_module(_node, _module, _docs, _specs, _path), do: []

  # ---------------------------------------------------------------------------
  # Helpers de AST
  # ---------------------------------------------------------------------------

  # `{:__aliases__, _, [:Foo, :Bar, :Baz]}` → "Foo.Bar.Baz"
  defp aliases_to_string({:__aliases__, _, parts}) do
    parts
    |> Enum.map(fn
      a when is_atom(a) -> Atom.to_string(a)
      {:__aliases__, _, [single]} -> atom_or_string(single)
      other -> inspect(other)
    end)
    |> Enum.join(".")
  end

  defp aliases_to_string(other), do: inspect(other)

  # Extrae el nombre de un def del AST.
  # AST: {:def, meta, [name_node | guards_with_default], [do: body]}
  # donde name_node es {:name, _, args} o {:name, _, [args], guard} o
  # {:name, meta, [args, ...]} según la versión.
  #
  # El primer elemento del array args_ast es siempre el "name call",
  # algo como `{:foo, _, []}` o `{:+, _, [a, b]}`.
  defp infer_def_name(args_ast) when is_list(args_ast) do
    case List.first(args_ast) do
      {name, _, _} when is_atom(name) -> Atom.to_string(name)
      _ -> nil
    end
  end

  defp infer_def_name(_), do: nil

  # Convierte {:name, _, _} a "name" o a atom
  defp atom_or_string({:__aliases__, _, [a]}) when is_atom(a), do: Atom.to_string(a)
  defp atom_or_string(a) when is_atom(a), do: Atom.to_string(a)
  defp atom_or_string(s) when is_binary(s), do: s
  defp atom_or_string(other), do: inspect(other)

  # ---------------------------------------------------------------------------
  # Helpers de línea / annotation
  # ---------------------------------------------------------------------------

  # El AST de Elixir no siempre tiene :line_end (solo algunas
  # versiones lo emiten). Si no está, estimamos con el contexto del
  # path: usamos el final del archivo como cota superior. Pero
  # normalmente está disponible con `columns: true`.
  defp meta_to_line_end(meta, path) do
    case meta[:line_end] do
      nil ->
        # Fallback: contar líneas del archivo entero
        case File.read(path) do
          {:ok, content} -> content |> String.split("\n") |> length()
          _ -> meta[:line] || 1
        end

      line -> line
    end
  end

  # Pre-procesa el archivo extrayendo `@doc """..."""` por línea.
  # Devuelve %{line => doc_string}.
  defp extract_docs_per_line(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.trim(line) =~ ~r/^@(doc|moduledoc)\s/ end)
    |> Enum.map(fn {line, lineno} -> {lineno, extract_quoted(line)} end)
    |> Enum.reject(fn {_l, doc} -> is_nil(doc) end)
    |> Map.new()
  end

  # Extrae `@spec ...` por línea. El spec puede ser una sola línea o
  # multilínea (`@spec f(integer) :: integer` con `do:` block).
  # Devuelve %{line => spec_string}.
  defp extract_specs_per_line(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.trim(line) =~ ~r/^@spec\s/ end)
    |> Enum.map(fn {line, lineno} -> {lineno, extract_quoted(line)} end)
    |> Enum.reject(fn {_l, spec} -> is_nil(spec) end)
    |> Map.new()
  end

  # Extrae la parte entre `"""` de una línea `@doc """..."""`.
  # Si la línea tiene solo `@doc "..."`, devuelve eso.
  # Si tiene `@doc """..."""`, devuelve el contenido.
  defp extract_quoted(line) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "@doc ") ->
        extract_doc_string(trimmed, "@doc ")

      String.starts_with?(trimmed, "@moduledoc ") ->
        extract_doc_string(trimmed, "@moduledoc ")

      String.starts_with?(trimmed, "@spec ") ->
        String.replace_prefix(trimmed, "@spec ", "")

      true ->
        nil
    end
  end

  # Extrae el contenido entre comillas triples o simples.
  defp extract_doc_string(line, prefix) do
    rest = String.replace_prefix(line, prefix, "")

    cond do
      String.starts_with?(rest, ~s(""\")) and String.ends_with?(rest, ~s(""\")) ->
        # "" "..." "" → strip las dos triples de cada lado
        rest
        |> String.replace_prefix(~s(""\"\"), "")
        |> String.replace_suffix(~s(""\"\"), "")

      String.starts_with?(rest, ~s(")) ->
        # "..." → strip comillas simples
        rest |> String.replace_prefix(~s("), "") |> String.replace_suffix(~s("), "")

      true ->
        rest
    end
  end

  # Busca la anotación inmediatamente anterior a `line`.
  # Las annotations son por línea, así que devolvemos la que está
  # más cerca sin pasarse.
  defp find_annotation_above(per_line, line) do
    per_line
    |> Enum.filter(fn {l, _} -> l < line end)
    |> Enum.max_by(fn {l, _} -> l end, fn -> {line, nil} end)
    |> elem(1)
  end

  # ---------------------------------------------------------------------------
  # TODOs
  # ---------------------------------------------------------------------------

  defp extract_todos(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end

  defp collect_doc_strings(docs_per_line) do
    docs_per_line
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim/1)
  end

  # ---------------------------------------------------------------------------
  # Build symbol
  # ---------------------------------------------------------------------------

  # Construye un mapa símbolo con los campos esperados por el indexer.
  # El campo `line_end` (C3) se incluye aquí; el dispatcher/inserter lo
  # acepta como opcional y persiste si está presente.
  defp build_symbol(kind, name, line_start, line_end, path, module, visibility, doc, spec) do
    qualified =
      if module && kind not in ["module", "use", "behaviour"],
        do: "#{module}.#{name}",
        else: name

    %{
      name: name,
      qualified_name: qualified,
      kind: kind,
      visibility: visibility,
      line_start: line_start,
      line_end: line_end,
      language: "elixir",
      docstring: doc,
      signature: spec,
      metadata: %{module: module, file: path}
    }
  end
end
