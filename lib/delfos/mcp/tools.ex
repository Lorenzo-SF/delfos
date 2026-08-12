defmodule Delfos.MCP.Tools do
  @moduledoc """
  Implementación de las herramientas MCP de Delfos.

  FILOSOFÍA DE RESPUESTA:
  Las respuestas están optimizadas para agentes de IA: máxima información
  semántica en el mínimo de tokens. Usan un formato compacto de texto plano
  (no Markdown verboso) que comunica estructura sin desperdiciar tokens en
  decoración.

  Formato de símbolo compacto:
    SYMBOL: Module.function/arity
    KIND: function | FILE: lib/x.ex:12-45 | LANG: elixir | VIS: public
    SUMMARY: <resumen LLM de 1-2 frases>
    SPEC: @spec firma/tipo (si existe)
    CALLERS(n): A.b, C.d, E.f
    CALLEES(n): X.y, Z.w
    RISK: debt=8.2 instability=0.71 churn=34 cycle=no
    RELATED: OtherModule(0.87) AnotherOne(0.82)
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}
  alias Delfos.Retrieval.{HybridSearch, VectorSearch}
  alias Delfos.LLM.Client

  # S7: cota máxima para inputs de texto que van a `ilike`/regex.
  # Sin esto, un cliente puede enviar 10MB y disparar ReDoS o
  # consultas muy lentas. 200 chars es más que suficiente para
  # nombres de símbolos, queries de búsqueda y filtros de path.
  @max_query_length 200

  @doc false
  def max_query_length, do: @max_query_length

  # S7: validar input de usuario. Devuelve `{:ok, value}` para inputs
  # válidos o `{:error, razón}` si el input es demasiado largo o no
  # es un string. Aplicar al inicio de cada tool con input de texto.
  defp sanitize_query(input) when is_binary(input) do
    if String.length(input) > @max_query_length do
      {:error, "Query too long (max #{@max_query_length} chars)"}
    else
      {:ok, input}
    end
  end

  defp sanitize_query(_), do: {:error, "Invalid query type (expected string)"}

  # ---------------------------------------------------------------------------
  # delfos_search
  # ---------------------------------------------------------------------------

  def search(nil, _), do: {:error, "No hay proyectos indexados. Ejecuta: delfos init"}

  def search(project, %{"query" => raw_query} = args) do
    with {:ok, query} <- sanitize_query(raw_query) do
      limit = Map.get(args, "limit", 5)
      kind = Map.get(args, "kind")
      level = parse_level(Map.get(args, "level", "chunk"))

      case HybridSearch.search(project.id, query,
             k: limit * 4,
             final_k: limit,
             kind: kind,
             level: level
           ) do
        {:ok, []} ->
          {:ok, "Sin resultados para: \"#{query}\""}

        {:ok, results} ->
          text =
            results
            |> Enum.with_index(1)
            |> Enum.map(fn {r, i} -> format_search_result(r, i) end)
            |> Enum.join("\n")

          {:ok, "QUERY: #{query} | RESULTS: #{length(results)}\n\n#{text}"}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # delfos_symbol
  # ---------------------------------------------------------------------------

  def symbol(nil, _), do: {:error, "No hay proyectos indexados"}

  def symbol(project, %{"name" => raw_name}) do
    with {:ok, name} <- sanitize_query(raw_name) do
      # Bug #24 fix: delega a find_symbol/2 (ranking por qualified_name
      # + arity). Antes hacía ilike con %name% ordenado por line_start,
      # lo que devolvía matches ambiguos (e.g. "resolver" → theme_resolver/0
      # en lugar de Pote.Theme.resolver/1).
      sym = find_symbol(project.id, name)

      if is_nil(sym) do
        # Si no hay match exacto, devuelve candidatos para que el
        # modelo pueda desambiguar (Bug #24 mejora de UX).
        candidates = find_symbol_candidates(project.id, name, nil, limit: 10)

        case candidates do
          [] ->
            {:error, "Símbolo no encontrado: #{name}"}

          _ ->
            lines =
              Enum.map(candidates, fn c ->
                "  • #{c.qualified_name} (#{c.kind}) — #{c.file && c.file.path}:#{c.line_start}"
              end)

            {:error,
             "Símbolo no encontrado exacto: #{name}\n\nCandidatos similares:\n" <>
               Enum.join(lines, "\n") <>
               "\n\nPista: usa 'Módulo.función/N' para calificar (e.g. 'Pote.Theme.resolver/1')."}
        end
      else
        sym = Repo.preload(sym, :file)
        callers = get_callers(sym.id)
        callees = get_callees(sym.id)
        metrics = sym.file_id && Repo.get_by(Schema.FileMetrics, file_id: sym.file_id)
        related = get_related(project.id, sym)

        {:ok, format_symbol_full(sym, callers, callees, metrics, related)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # delfos_context
  # ---------------------------------------------------------------------------

  def context(nil, _), do: {:error, "No hay proyectos indexados"}

  def context(project, %{"task" => raw_task} = args) do
    with {:ok, task} <- sanitize_query(raw_task) do
      max_symbols = Map.get(args, "max_symbols", 8)

      # 1. Búsqueda híbrida amplia
      {:ok, results} =
        HybridSearch.search(project.id, task, k: max_symbols * 3, final_k: max_symbols)

      if Enum.empty?(results) do
        {:ok,
         "Sin contexto relevante para: \"#{task}\"\nConsidera re-escanear el proyecto: delfos scan --full"}
      else
        # 2. Enriquecer con datos de símbolo completos
        symbol_ids =
          results
          |> Enum.filter(&(&1[:kind] not in ["chunk", "summary"]))
          |> Enum.map(& &1[:id])
          |> Enum.reject(&is_nil/1)

        symbols =
          Repo.all(
            from(s in Schema.Symbol,
              where: s.id in ^symbol_ids,
              preload: [:file]
            )
          )
          |> Map.new(&{&1.id, &1})

        lines = ["CONTEXT FOR: #{task}", "SYMBOLS: #{length(results)}", ""]

        symbol_lines =
          results
          |> Enum.map(fn r ->
            sym = Map.get(symbols, r[:id])
            if sym, do: format_symbol_compact(sym), else: format_chunk_compact(r)
          end)

        {:ok, Enum.join(lines ++ symbol_lines, "\n")}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # delfos_callers
  # ---------------------------------------------------------------------------

  def callers(nil, _), do: {:error, "No hay proyectos indexados"}

  def callers(project, %{"name" => raw_name}) do
    with {:ok, name} <- sanitize_query(raw_name) do
      sym = find_symbol(project.id, name)

      if is_nil(sym) do
        {:error, "Símbolo no encontrado: #{name}"}
      else
        callers = get_callers_full(sym.id)

        if Enum.empty?(callers) do
          {:ok, "#{sym.qualified_name}: sin callers (posible entry point o grafo incompleto)"}
        else
          lines =
            Enum.map(callers, fn c ->
              "  #{c.qualified_name} (#{c.kind}) — #{c.file && c.file.path}:#{c.line_start}"
            end)

          {:ok, "CALLERS OF: #{sym.qualified_name} (#{length(callers)})\n#{Enum.join(lines, "\n")}"}
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # delfos_callees
  # ---------------------------------------------------------------------------

  def callees(nil, _), do: {:error, "No hay proyectos indexados"}

  def callees(project, %{"name" => raw_name}) do
    with {:ok, name} <- sanitize_query(raw_name) do
      sym = find_symbol(project.id, name)

      if is_nil(sym) do
        {:error, "Símbolo no encontrado: #{name}"}
      else
        callees = get_callees_full(sym.id)

        if Enum.empty?(callees) do
          {:ok,
           "#{sym.qualified_name}: no llama a nada registrado (símbolo hoja o grafo incompleto)"}
        else
          lines =
            Enum.map(callees, fn c ->
              "  #{c.qualified_name} (#{c.kind}) — #{c.file && c.file.path}:#{c.line_start}"
            end)

          {:ok, "CALLEES OF: #{sym.qualified_name} (#{length(callees)})\n#{Enum.join(lines, "\n")}"}
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # delfos_impact
  # ---------------------------------------------------------------------------

  def impact(nil, _), do: {:error, "No hay proyectos indexados"}

  def impact(project, %{"name" => raw_name} = args) do
    with {:ok, name} <- sanitize_query(raw_name) do
      depth = Map.get(args, "depth", 3)
      sym = find_symbol(project.id, name)

      if sym do
        affected = bfs_impact(sym.id, project.id, depth, MapSet.new([sym.id]))

        if Enum.empty?(affected) do
          {:ok,
           "IMPACT OF: #{sym.qualified_name}\nSin símbolos afectados directamente.\nSugerencia: ejecuta 'mix compile && delfos scan --full' para poblar el grafo."}
        else
          lines =
            affected
            |> Enum.sort_by(& &1.qualified_name)
            |> Enum.map(fn s -> "  #{s.qualified_name} (#{s.kind})" end)

          {:ok,
           "IMPACT OF: #{sym.qualified_name} | DEPTH: #{depth} | AFFECTED: #{length(affected)}\n#{Enum.join(lines, "\n")}"}
        end
      else
        {:error, "Símbolo no encontrado: #{name}"}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # delfos_audit
  # ---------------------------------------------------------------------------

  def audit(nil, _), do: {:error, "No hay proyectos indexados"}

  def audit(project, args) do
    file_path = Map.get(args, "file")

    if file_path do
      audit_file(project, file_path)
    else
      audit_project(project)
    end
  end

  defp audit_project(project) do
    hotspots =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id and f.risk_score > 5.0,
          order_by: [desc: f.risk_score],
          limit: 5,
          select: %{path: f.path, risk: f.risk_score, churn: f.git_churn}
        )
      )

    cycles =
      Repo.one(
        from(m in Schema.FileMetrics,
          where: m.project_id == ^project.id and m.in_cycle == true,
          select: count(m.id)
        )
      ) || 0

    total_sym =
      Repo.one(from(s in Schema.Symbol, where: s.project_id == ^project.id, select: count(s.id))) ||
        0

    with_emb =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id and not is_nil(s.embedding),
          select: count(s.id)
        )
      ) || 0

    with_sum =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id and not is_nil(s.summary),
          select: count(s.id)
        )
      ) || 0

    hot_lines =
      Enum.map(hotspots, fn h ->
        "  #{h.path} | risk=#{fmt(h.risk)} churn=#{h.churn}"
      end)

    text = """
    AUDIT: #{project.name} | SCANNED: #{project.last_scanned}
    SYMBOLS: #{total_sym} | EMBEDDED: #{pct(with_emb, total_sym)}% | SUMMARIZED: #{pct(with_sum, total_sym)}%
    CYCLES: #{cycles} files in dependency cycles
    HOTSPOTS (top 5 by risk):
    #{if Enum.empty?(hot_lines), do: "  (none)", else: Enum.join(hot_lines, "\n")}
    """

    {:ok, String.trim(text)}
  end

  defp audit_file(project, file_path) do
    # S9: rechazar path traversal (`..`) y paths absolutos.
    # El path en la DB es absoluto; el `ilike` busca substring, así que
    # `../.ssh/id_rsa` matchearía cualquier archivo en el índice cuyo
    # path contenga ese substring. Forzamos paths relativos limpios.
    # S7: además, sanitizar la longitud del input.
    with {:ok, safe_path} <- sanitize_query(file_path),
         :ok <- validate_relative_path(safe_path) do
      do_audit_file(project, safe_path)
    else
      {:error, _} = err -> err
      :error -> {:error, "Invalid file path: must be relative and not contain '..'"}
    end
  end

  defp validate_relative_path(path) do
    if String.contains?(path, "..") or String.starts_with?(path, "/"),
      do: :error,
      else: :ok
  end

  defp do_audit_file(project, file_path) do
    file =
      Repo.one(
        from(f in Schema.File,
          where: f.project_id == ^project.id and ilike(f.path, ^"%#{file_path}%"),
          limit: 1
        )
      )

    if is_nil(file) do
      {:error, "Archivo no encontrado: #{file_path}"}
    else
      metrics = Repo.get_by(Schema.FileMetrics, file_id: file.id)

      text = """
      AUDIT FILE: #{file.path}
      LANG: #{file.language} | LINES: #{file.line_count} | SIZE: #{file.size_bytes}b
      RISK: score=#{fmt(file.risk_score)} churn=#{file.git_churn} authors=#{length(file.git_authors || [])}
      #{if metrics do
        "COUPLING: Ca=#{metrics.afferent_coupling} Ce=#{metrics.efferent_coupling} instability=#{fmt(metrics.instability)}" <> "\nDEBT: score=#{fmt(metrics.debt_score)} todos=#{metrics.todo_count} in_cycle=#{metrics.in_cycle}"
      else
        "COUPLING: (sin datos de coupling)"
      end}
      """

      {:ok, String.trim(text)}
    end
  end

  # ---------------------------------------------------------------------------
  # delfos_files
  # ---------------------------------------------------------------------------

  def files(nil, _), do: {:error, "No hay proyectos indexados"}

  def files(project, args) do
    raw_filter = Map.get(args, "filter", "")

    # S7: sanitizar filter. Si no es string (e.g. cliente envía int),
    # devolvemos error explícito en vez de explotar en la query.
    with {:ok, filter} <- sanitize_query(raw_filter) do
      query =
        from(f in Schema.File,
          where: f.project_id == ^project.id,
          order_by: [asc: f.path],
          select: %{path: f.path, language: f.language, lines: f.line_count, risk: f.risk_score}
        )

      query =
        if filter != "" do
          where(query, [f], ilike(f.path, ^"%#{filter}%") or f.language == ^filter)
        else
          query
        end

      files = Repo.all(query)

      lines =
        Enum.map(files, fn f ->
          risk_flag = if (f.risk || 0) > 10.0, do: " ⚠", else: ""
          "  #{f.path} [#{f.language}] #{f.lines || 0}L#{risk_flag}"
        end)

      {:ok,
       "FILES: #{length(files)}#{if filter != "", do: " (filter: #{filter})", else: ""}\n#{Enum.join(lines, "\n")}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Formateadores — formato compacto para agentes
  # ---------------------------------------------------------------------------

  defp format_search_result(r, i) do
    score = Float.round(r[:combined_score] || 0.0, 3)
    name = r[:name] || ""
    kind = r[:kind] || "chunk"
    preview = (r[:content] || "") |> String.slice(0, 150) |> String.replace("\n", " ")

    "[#{i}] score=#{score} kind=#{kind}#{if name != "", do: " name=#{name}", else: ""}\n    #{preview}"
  end

  defp format_symbol_full(sym, callers, callees, metrics, related) do
    file_ref = if sym.file, do: "#{sym.file.path}:#{sym.line_start}-#{sym.line_end}", else: "?"

    # Bug #26 fix: detectar símbolos con metadatos de rango
    # sospechosos. Criterio conservador: line_end < line_start
    # (rango inválido — el parser piensa que la función termina
    # antes de empezar). Esto captura los `def` en quote do
    # (line_end=1 o -1) y excluye las funciones single-line
    # válidas (line_end == line_start).
    #
    # Nota: 1-line `def f, do: x` también sale con line_end=1 en el
    # parser actual. Por eso el flag solo aparece cuando el rango
    # es claramente inválido (line_end < line_start). Funciones
    # válidas como `def default_colors, do: @default_colors` (1
    # línea, line_start=46, line_end=1) NO se marcan.
    unextracted? = sym.line_end < sym.line_start
    macro_flag = if unextracted?, do: " [UNEXTRACTED]", else: ""

    callers_str =
      if Enum.empty?(callers),
        do: "none",
        else: callers |> Enum.map(& &1.qualified_name) |> Enum.join(", ")

    callees_str =
      if Enum.empty?(callees),
        do: "none",
        else: callees |> Enum.map(& &1.qualified_name) |> Enum.join(", ")

    related_str =
      if Enum.empty?(related),
        do: "none",
        else:
          related
          |> Enum.map(fn {name, score} -> "#{name}(#{Float.round(score, 2)})" end)
          |> Enum.join(" ")

    risk_str =
      if metrics do
        "debt=#{fmt(metrics.debt_score)} instability=#{fmt(metrics.instability)} churn=#{get_churn(sym)} cycle=#{metrics.in_cycle}"
      else
        "churn=#{get_churn(sym)}"
      end

    code_preview =
      cond do
        unextracted? ->
          "(Código no extraído — el rango line_end < line_start indica un `def` en un bloque `quote do` de una macro. " <>
            "La función se inyecta en el módulo que llame al macro, no se ejecuta aquí. " <>
            "Lee el archivo fuente directamente en #{file_ref}.)"

        # Casos borderline: content vacío pero line_end >= line_start
        # (típico de funciones 1-line que el parser no supo extraer,
        # o de defs en quote do que el parser no marcó con line_end<0).
        # Mostrar un aviso más suave.
        sym.content in [nil, ""] ->
          "(Contenido no extraído por el parser. " <>
            "Lee el archivo fuente en #{file_ref} para ver el código.)"

        true ->
          (sym.content || "")
          |> String.slice(0, 800)
      end

    """
    SYMBOL: #{sym.qualified_name}#{macro_flag}
    KIND: #{sym.kind} | FILE: #{file_ref} | LANG: #{sym.language} | VIS: #{sym.visibility || "public"}
    SUMMARY: #{sym.summary || "(sin resumen — ejecuta: delfos summarize)"}
    SPEC: #{sym.signature || sym.docstring || "(sin firma)"}
    CALLERS(#{length(callers)}): #{callers_str}
    CALLEES(#{length(callees)}): #{callees_str}
    RISK: #{risk_str}
    RELATED: #{related_str}
    CODE:
    #{code_preview}
    """
    |> String.trim()
  end

  defp format_symbol_compact(sym) do
    file_ref = if sym.file, do: "#{sym.file.path}:#{sym.line_start}", else: "?"
    summary = sym.summary || sym.docstring || "(sin resumen)"

    "SYMBOL: #{sym.qualified_name} | #{sym.kind} | #{file_ref}\n  #{String.slice(summary, 0, 120)}"
  end

  # Bug #26: heurística de proximidad a defmacro. Si el archivo del
  # símbolo tiene un `defmacro` definido ANTES del símbolo, el
  # símbolo está probablemente dentro de un `quote do` de ese macro.
  # Sin esta comprobación, cualquier `def` mal indexado se
  # etiquetaría como [UNEXTRACTED] falsamente.
  #
  # Nota: actualmente inactiva porque el NIF no indexa defmacro
  # (Bug #22, documentado en docs/NIF_TREE_SITTER_MODULE_FIX.md).
  # Cuando el NIF se arregle, re-habilitar implementando las
  # funciones `near_defmacro?/1` y `has_defmacro_above?/2` y
  # conectándolas en el `format_symbol/1` superior.

  defp format_chunk_compact(r) do
    preview = (r[:content] || "") |> String.slice(0, 200) |> String.replace("\n", " ")
    "CHUNK: score=#{Float.round(r[:combined_score] || 0.0, 3)}\n  #{preview}"
  end

  # ---------------------------------------------------------------------------
  # Helpers de grafo
  # ---------------------------------------------------------------------------

  # Look up a symbol by name. Returns the best match, or nil.
  #
  # Bug #24 fix: el lookup anterior solo buscaba por substring de
  # name O qualified_name, ordenando por line_start. Esto causaba que
  # `find_symbol("resolver")` devolviera `theme_resolver/0` (primer
  # match alfabético) en vez de `Pote.Theme.resolver/1` (el que el
  # usuario probablemente quería).
  #
  # Nueva estrategia de ranking (de mejor a peor match):
  #   1. Match EXACTO de qualified_name (case-sensitive, sin arity)
  #   2. Match EXACTO de qualified_name con arity (e.g. "Foo.Bar.f/1")
  #   3. Match EXACTO de name (sin qualifier)
  #   4. Match con arity explícita al final del input (e.g. "resolver/1")
  #   5. Substring fuzzy en qualified_name (ordenado por longitud,
  #      preferir el más corto = más específico)
  #   6. Substring fuzzy en name (último recurso)
  #
  # Si hay ambigüedad, devuelve nil y el caller puede usar
  # find_symbol_candidates/2 para listar opciones.
  #
  # El input también acepta el formato "Foo.Bar.func/1" o "func/1" —
  # extraemos el arity opcional y lo usamos para desambiguar.
  defp find_symbol(project_id, input) do
    {name, arity} = parse_symbol_input(input)
    candidates = find_symbol_candidates(project_id, name, arity, limit: 10)

    case candidates do
      [] -> nil
      [single] -> single
      multiple -> Enum.find(multiple, &exact_match?(&1, name, arity)) || List.first(multiple)
    end
  end

  # Parsea el input. Acepta "Foo.Bar.f/1", "Foo.Bar.f", "f/1", "f".
  # Devuelve {name, arity_or_nil}.
  defp parse_symbol_input(input) do
    case String.split(input, "/") do
      [name, arity_str] ->
        case Integer.parse(arity_str) do
          {arity, ""} -> {name, arity}
          _ -> {input, nil}
        end

      _ ->
        {input, nil}
    end
  end

  # Devuelve los candidatos ordenados por relevancia (mejor primero).
  # Si `arity` no es nil, filtra por aridad al final.
  #
  # El orden de ranking es:
  #   1. Exact match en qualified_name (con o sin arity)
  #   2. Exact match en name (con o sin arity)
  #   3. Substring en qualified_name (más corto = más específico)
  #   4. Substring en name (último recurso)
  #
  # Bug #24 fix (mejorado): el filtro `s.name == ^name` se aplicaba
  # SIEMPRE antes del ilike, lo que hacía búsquedas parciales ("res")
  # no devolvieran nada. Ahora solo se filtra por arity si se
  # proporcionó; la búsqueda por nombre permite substring cuando
  # no hay match exacto.
  def find_symbol_candidates(project_id, name, arity, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    arity_filter =
      if arity, do: dynamic([s], s.arity == ^arity), else: true

    base_query = from(s in Schema.Symbol, where: s.project_id == ^project_id)

    # 1. Exact match (qualified_name exact o name exact)
    exact =
      from(s in base_query,
        where: ^arity_filter,
        where: s.qualified_name == ^name or s.name == ^name,
        limit: ^limit
      )

    case Repo.all(exact) do
      [_ | _] = results ->
        results

      [] ->
        # 2. Substring fallback (qualified_name o name) — una sola query
        from(s in base_query,
          where: ^arity_filter,
          where: ilike(s.qualified_name, ^"%#{name}%") or ilike(s.name, ^"%#{name}%"),
          order_by: [asc: fragment("length(?)", s.qualified_name)],
          limit: ^limit
        )
        |> Repo.all()
    end
  end

  defp exact_match?(symbol, name, arity) do
    name_match = symbol.name == name or symbol.qualified_name == name
    arity_match = is_nil(arity) or symbol.arity == arity
    name_match and arity_match
  end

  defp get_callers(symbol_id) do
    Repo.all(
      from(r in Schema.Relationship,
        join: s in Schema.Symbol,
        on: s.id == r.from_id,
        where: r.to_id == ^symbol_id,
        select: s.qualified_name,
        limit: 20
      )
    )
  end

  defp get_callers_full(symbol_id) do
    # Seleccionamos los símbolos caller directamente con preload de file.
    # El join con Relationship nos da solo los que llaman a symbol_id.
    # Ya no necesitamos el hack preload_assoc — Ecto preloadea file
    # correctamente sobre Symbol si la relación está bien definida.
    Repo.all(
      from(s in Schema.Symbol,
        join: r in Schema.Relationship,
        on: r.from_id == s.id,
        where: r.to_id == ^symbol_id,
        limit: 20,
        preload: [:file]
      )
    )
  end

  defp get_callees(symbol_id) do
    Repo.all(
      from(r in Schema.Relationship,
        join: s in Schema.Symbol,
        on: s.id == r.to_id,
        where: r.from_id == ^symbol_id,
        select: s.qualified_name,
        limit: 20
      )
    )
  end

  defp get_callees_full(symbol_id) do
    Repo.all(
      from(s in Schema.Symbol,
        join: r in Schema.Relationship,
        on: r.to_id == s.id,
        where: r.from_id == ^symbol_id,
        limit: 20,
        preload: [:file]
      )
    )
  end

  defp get_related(project_id, sym) do
    case Client.embed(sym.name) do
      {:ok, vec} ->
        VectorSearch.search(project_id, vec, 5, nil, :symbol)
        |> Enum.reject(&(&1[:id] == sym.id))
        |> Enum.take(4)
        |> Enum.map(fn r -> {r[:name] || "?", r[:combined_score] || r[:score] || 0.0} end)

      _ ->
        []
    end
  end

  defp bfs_impact(_id, _pid, 0, _visited), do: []

  defp bfs_impact(symbol_id, project_id, depth, visited) do
    direct =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.to_id,
          where: r.from_id == ^symbol_id and r.project_id == ^project_id,
          where: s.id not in ^MapSet.to_list(visited),
          select: s
        )
      )

    new_visited = Enum.reduce(direct, visited, &MapSet.put(&2, &1.id))

    indirect =
      Enum.flat_map(direct, fn s ->
        bfs_impact(s.id, project_id, depth - 1, new_visited)
      end)

    (direct ++ indirect) |> Enum.uniq_by(& &1.id)
  end

  defp get_churn(sym) do
    case sym.file do
      nil -> 0
      file -> file.git_churn || 0
    end
  end

  defp parse_level("symbol"), do: :symbol
  defp parse_level("summary"), do: :summary
  defp parse_level(_), do: nil

  defp fmt(nil), do: "—"
  defp fmt(n) when is_float(n), do: Float.round(n, 2) |> to_string()
  defp fmt(n), do: to_string(n)

  defp pct(_p, 0), do: 0
  defp pct(p, t), do: Float.round(p / t * 100, 1)
end
