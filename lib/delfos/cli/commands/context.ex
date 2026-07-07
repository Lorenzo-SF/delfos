defmodule Delfos.CLI.Commands.Context do
  alias Alaja

  @moduledoc """
  Genera AGENTS.md y CLAUDE.md con información rica del proyecto para agentes de IA.

  Con --symbol <nombre> genera contexto dinámico centrado en ese símbolo:
  código, callers, callees, métricas y chunks relevantes.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  @help """
  USAGE
      delfos context [flags]

  Generate AGENTS.md / CLAUDE.md from the index for AI agents.

  FLAGS
      --output <dir>    Output directory (default: cwd)
      --symbol <name>   Focus context on a specific symbol
      --format <fmt>    Output format: markdown (default) | json
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  # Legacy argv entry point — kept for backward compat.
  def run(args) when is_list(args) do
    {opts, _, _} =
      OptionParser.parse(args, switches: [output: :string, symbol: :string, format: :string])

    run_with_opts(opts)
  end

  @doc """
  Runs context generation with pre-parsed options.
  """
  def run_with_opts(opts) when is_map(opts) do
    output_dir = Map.get(opts, :output) || File.cwd!()
    symbol_name = Map.get(opts, :symbol)
    format = Map.get(opts, :format, "markdown")

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Alaja.print_info("No hay proyectos. Usa delfos init")
      System.halt(1)
    end

    if symbol_name do
      generate_symbol_context(project, symbol_name, format)
    else
      generate_project_context(project, output_dir)
    end
  end

  # ---------------------------------------------------------------------------
  # Contexto de proyecto completo → AGENTS.md + CLAUDE.md
  # ---------------------------------------------------------------------------

  defp generate_project_context(project, output_dir) do
    stats = get_stats(project)
    hotspots = get_hotspots(project)
    module_tree = get_module_tree(project)
    debt_summary = get_debt_summary(project)
    stacks = get_stack_breakdown(project)
    entry_points = get_entry_points(project)

    briefing =
      generate_briefing(project, stats, hotspots, module_tree, debt_summary, stacks, entry_points)

    agents_path = Path.join([output_dir, ".opencode", "AGENTS.md"])
    claude_path = Path.join([output_dir, ".claude", "CLAUDE.md"])

    File.mkdir_p!(Path.dirname(agents_path))
    File.mkdir_p!(Path.dirname(claude_path))

    File.write!(agents_path, briefing)

    File.write!(
      claude_path,
      briefing <> "\n## Rutas\nArtefactos en `../.code-intel/` si existen.\n"
    )

    Alaja.print_info("Generado:\n  #{agents_path}\n  #{claude_path}")
  end

  defp get_stats(project) do
    %{
      files:
        Repo.one(from(f in Schema.File, where: f.project_id == ^project.id, select: count(f.id))),
      symbols:
        Repo.one(
          from(s in Schema.Symbol, where: s.project_id == ^project.id, select: count(s.id))
        ),
      functions:
        Repo.one(
          from(s in Schema.Symbol,
            where: s.project_id == ^project.id and s.kind == "function",
            select: count(s.id)
          )
        ),
      modules:
        Repo.one(
          from(s in Schema.Symbol,
            where: s.project_id == ^project.id and s.kind == "module",
            select: count(s.id)
          )
        ),
      todos:
        Repo.one(
          from(s in Schema.Symbol,
            where: s.project_id == ^project.id,
            where: fragment("? ~* ?", s.content, "TODO|FIXME|HACK"),
            select: count(s.id)
          )
        ),
      with_summary:
        Repo.one(
          from(s in Schema.Symbol,
            where: s.project_id == ^project.id and not is_nil(s.summary),
            select: count(s.id)
          )
        )
    }
  end

  defp get_hotspots(project) do
    Repo.all(
      from(f in Schema.File,
        where: f.project_id == ^project.id and f.risk_score > 5.0,
        order_by: [desc: f.risk_score],
        limit: 10,
        select: %{path: f.path, risk: f.risk_score, churn: f.git_churn}
      )
    )
  end

  defp get_module_tree(project) do
    # Top-level modules agrupados por namespace
    Repo.all(
      from(s in Schema.Symbol,
        where: s.project_id == ^project.id and s.kind == "module",
        order_by: s.qualified_name,
        select: {s.qualified_name, s.line_start},
        limit: 60
      )
    )
    |> Enum.group_by(fn {name, _} ->
      name |> String.split(".") |> List.first()
    end)
  end

  defp get_debt_summary(project) do
    Repo.all(
      from(m in Schema.FileMetrics,
        join: f in Schema.File,
        on: f.id == m.file_id,
        where: m.project_id == ^project.id and m.debt_score > 5.0,
        order_by: [desc: m.debt_score],
        limit: 5,
        select: %{
          path: f.path,
          debt: m.debt_score,
          instability: m.instability,
          in_cycle: m.in_cycle
        }
      )
    )
  end

  defp get_stack_breakdown(project) do
    Repo.all(
      from(f in Schema.File,
        where: f.project_id == ^project.id,
        group_by: f.language,
        select: {f.language, count(f.id)}
      )
    )
  end

  defp get_entry_points(project) do
    # Símbolos públicos sin callers entrantes = posibles entry points
    Repo.all(
      from(s in Schema.Symbol,
        left_join: r in Schema.Relationship,
        on: r.to_id == s.id,
        where: s.project_id == ^project.id,
        where: s.kind in ["function", "module"] and s.visibility == "public",
        where: is_nil(r.id),
        order_by: s.qualified_name,
        limit: 15,
        select: {s.qualified_name, s.kind}
      )
    )
  end

  defp generate_briefing(
         project,
         stats,
         hotspots,
         module_tree,
         debt_summary,
         stacks,
         entry_points
       ) do
    hot_list =
      Enum.map(
        hotspots,
        &"- `#{&1.path}` (risk: #{Float.round(&1.risk || 0.0, 1)}, churn: #{&1.churn})"
      )
      |> Enum.join("\n")

    module_tree_text =
      module_tree
      |> Enum.map(fn {ns, mods} ->
        sub = mods |> Enum.map(fn {name, _} -> "  - `#{name}`" end) |> Enum.join("\n")
        "- **#{ns}**\n#{sub}"
      end)
      |> Enum.join("\n")

    debt_text =
      Enum.map(debt_summary, fn d ->
        cycle_flag = if d.in_cycle, do: " ⚠️ ciclo", else: ""

        "- `#{d.path}` — debt: #{Float.round(d.debt || 0.0, 1)}, instability: #{Float.round(d.instability || 0.0, 2)}#{cycle_flag}"
      end)
      |> Enum.join("\n")

    stack_text =
      Enum.map(stacks, fn {lang, count} -> "- #{lang}: #{count} archivos" end)
      |> Enum.join("\n")

    entry_text =
      Enum.map(entry_points, fn {name, kind} -> "- `#{name}` (#{kind})" end)
      |> Enum.join("\n")

    coverage_pct =
      if stats.symbols > 0,
        do: Float.round((stats.with_summary || 0) / stats.symbols * 100, 1),
        else: 0.0

    """
    # #{project.name}

    > Generado por Delfos v#{Delfos.version()} — #{DateTime.utc_now() |> DateTime.to_iso8601()}

    ## Proyecto

    | Campo | Valor |
    |-------|-------|
    | Nombre | #{project.name} |
    | Stack principal | #{project.primary_stack} |
    | Archivos | #{stats.files} |
    | Símbolos totales | #{stats.symbols} |
    | Funciones | #{stats.functions} |
    | Módulos | #{stats.modules} |
    | TODOs/FIXMEs | #{stats.todos} |
    | Cobertura de resúmenes | #{coverage_pct}% |
    | Último scan | #{project.last_scanned} |

    ## Stack por lenguaje

    #{if stack_text == "", do: "- (sin datos)", else: stack_text}

    ## Árbol de módulos

    #{if module_tree_text == "", do: "- (sin módulos indexados)", else: module_tree_text}

    ## Posibles entry points (símbolos públicos sin callers)

    #{if entry_text == "", do: "- (ninguno detectado)", else: entry_text}

    ## Hotspots (archivos de alto riesgo de cambio)

    #{if hot_list == "", do: "- (ninguno)", else: hot_list}

    ## Archivos con mayor deuda técnica

    #{if debt_text == "", do: "- (ninguno)", else: debt_text}

    ## Consultas disponibles

    ```bash
    delfos query "tu búsqueda"
    delfos query "tu búsqueda" --level summary   # busca en resúmenes
    delfos audit                                  # deuda técnica completa
    delfos explain NombreModulo                   # explicación de un símbolo
    delfos graph callers NombreFuncion            # quién llama a una función
    delfos graph impact NombreFuncion             # qué se rompe si cambia
    delfos context --symbol NombreModulo          # contexto dinámico para agentes
    delfos summarize                              # generar/actualizar resúmenes LLM
    ```

    ## Convenciones detectadas

    - Lenguaje principal: **#{project.primary_stack}**
    - Visibilidad: símbolos privados prefijados con `_` (Python) o `defp` (Elixir)
    - TODOs marcados como `TODO`, `FIXME`, `HACK`, `DEBT`

    ## Reglas de trabajo

    1. Lee los hotspots antes de modificar esos archivos.
    2. Cambios atómicos: un PR, una intención.
    3. Tests para lógica de negocio nueva o modificada.
    4. Archivos marcados con ⚠️ ciclo tienen dependencias circulares — refactorizar con cuidado.
    """
  end

  # ---------------------------------------------------------------------------
  # Contexto dinámico para un símbolo concreto (--symbol)
  # ---------------------------------------------------------------------------

  defp generate_symbol_context(project, symbol_name, format) do
    symbol =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id,
          where:
            ilike(s.name, ^"%#{symbol_name}%") or ilike(s.qualified_name, ^"%#{symbol_name}%"),
          preload: [:file],
          limit: 1
        )
      )

    unless symbol do
      Alaja.print_info("Símbolo no encontrado: #{symbol_name}")
      System.halt(1)
    end

    callers =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.from_id,
          where: r.to_id == ^symbol.id,
          select: %{name: s.qualified_name, kind: s.kind}
        )
      )

    callees =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.to_id,
          where: r.from_id == ^symbol.id,
          select: %{name: s.qualified_name, kind: s.kind}
        )
      )

    metrics =
      symbol.file_id &&
        Repo.get_by(Schema.FileMetrics, file_id: symbol.file_id)

    # Búsqueda semántica de chunks relacionados
    related_chunks =
      case Delfos.LLM.Client.embed(symbol.name) do
        {:ok, vec} ->
          Delfos.Retrieval.VectorSearch.search(project.id, vec, 5, nil, nil)
          |> Enum.reject(&(&1.id == symbol.id))
          |> Enum.take(3)

        _ ->
          []
      end

    output = format_symbol_context(symbol, callers, callees, metrics, related_chunks, format)
    Alaja.print_raw(output)
  end

  defp format_symbol_context(symbol, callers, callees, metrics, related_chunks, _format) do
    callers_text =
      if Enum.empty?(callers),
        do: "  (ninguno)",
        else: Enum.map(callers, &"  - `#{&1.name}` (#{&1.kind})") |> Enum.join("\n")

    callees_text =
      if Enum.empty?(callees),
        do: "  (ninguno)",
        else: Enum.map(callees, &"  - `#{&1.name}` (#{&1.kind})") |> Enum.join("\n")

    metrics_text =
      if metrics do
        """
        - Afferent coupling: #{metrics.afferent_coupling}
        - Efferent coupling: #{metrics.efferent_coupling}
        - Instability: #{Float.round(metrics.instability || 0.0, 2)}
        - Debt score: #{Float.round(metrics.debt_score || 0.0, 1)}
        - En ciclo: #{if metrics.in_cycle, do: "⚠️ SÍ", else: "no"}
        """
      else
        "  (sin métricas)"
      end

    chunks_text =
      if Enum.empty?(related_chunks),
        do: "  (ninguno)",
        else:
          related_chunks
          |> Enum.map(&"  ```\n  #{String.slice(&1.content || "", 0, 200)}\n  ```")
          |> Enum.join("\n")

    """
    # Contexto: #{symbol.qualified_name}

    **Tipo:** #{symbol.kind} | **Lenguaje:** #{symbol.language} | **Visibilidad:** #{symbol.visibility}
    **Archivo:** #{symbol.file && symbol.file.path} (L#{symbol.line_start}–#{symbol.line_end})

    ## Docstring
    #{symbol.docstring || "(sin docstring)"}

    ## Resumen LLM
    #{symbol.summary || "(sin resumen — ejecuta `delfos summarize`)"}

    ## Código
    ```#{symbol.language}
    #{String.slice(symbol.content || "", 0, 2000)}
    ```

    ## Callers (quién llama a este símbolo)
    #{callers_text}

    ## Callees (qué llama este símbolo)
    #{callees_text}

    ## Métricas del archivo
    #{metrics_text}

    ## Chunks semánticamente relacionados
    #{chunks_text}
    """
  end
end
