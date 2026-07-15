defmodule Delfos.CLI.Commands.Agents do
  alias Alaja

  @moduledoc """
  Genera AGENTS.md y CLAUDE.md con información rica del proyecto para agentes de IA.

  Este es el comando que materializa el briefing del proyecto en
  artefactos que los agentes (opencode, claude-code, aider) leen
  automáticamente. Antes se llamaba `delfos context`; se renombró
  porque el nombre confundía: `context` sugiere "contexto dinámico
  para un símbolo" (que es lo que hace `--symbol`).

  Con --symbol <nombre> genera contexto dinámico centrado en ese
  símbolo: código, callers, callees, métricas y chunks relevantes.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  @help """
  USAGE
      delfos agents [flags]

  Generate AGENTS.md / CLAUDE.md from the index for AI agents.

  FLAGS
      --output <dir>    Output directory (default: cwd)

  Note: this command used to be called `delfos context`. The old name
  was preserved as a deprecation alias, but is now fully removed in
  v2.3.0. For symbol-focused context (callers, callees, metrics),
  use `delfos explain <name>` instead.
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  @doc """
  Runs context generation with pre-parsed options.

  Generates `AGENTS.md` + `CLAUDE.md` from the index for AI agents.
  For symbol-focused context (callers/callees/metrics/code), use
  `delfos explain <name>` instead (the legacy `--symbol` flag of
  `delfos agents` was removed in v2.3.0).
  """
  def run_with_opts(opts) when is_map(opts) do
    output_dir = Map.get(opts, :output) || File.cwd!()
    with_explanation? = Map.get(opts, :with_explanation, false) == true
    llm_less? = Map.get(opts, :llm_less, false) == true

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Alaja.print_info("No hay proyectos. Usa delfos init")
      System.halt(1)
    end

    generate_project_context(project, output_dir,
      with_explanation: with_explanation?,
      llm_less: llm_less?
    )
  end

  # ---------------------------------------------------------------------------
  # Contexto de proyecto completo → AGENTS.md + CLAUDE.md
  # ---------------------------------------------------------------------------

  defp generate_project_context(project, output_dir, opts) do
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

    claude_body = briefing <> "\n## Rutas\nArtefactos en `../.code-intel/` si existen.\n"

    claude_body =
      if Keyword.get(opts, :with_explanation, false) do
        cycles_count =
          Repo.one(
            from(m in Schema.FileMetrics,
              where: m.project_id == ^project.id and m.in_cycle == true,
              select: count(m.id)
            )
          ) || 0

        {:ok, executive} =
          Delfos.Agents.Executive.generate(
            %{
              name: project.name,
              files: stats.files,
              symbols: stats.symbols,
              cycles: cycles_count
            },
            llm_less: Keyword.get(opts, :llm_less, false)
          )

        "# Executive Summary (LLM)\n\n#{executive}\n\n" <> claude_body
      else
        claude_body
      end

    File.write!(claude_path, claude_body)

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
    delfos agents --symbol NombreModulo           # contexto dinámico para un símbolo
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
end
