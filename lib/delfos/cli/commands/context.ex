defmodule Delfos.CLI.Commands.Context do
  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [output: :string])
    output_dir = opts[:output] || File.cwd!()

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project,
      do:
        (
          IO.puts("No hay proyectos. Usa delfos init")
          System.halt(1)
        )

    stats = get_stats(project)
    hotspots = get_hotspots(project)
    briefing = generate_briefing(project, stats, hotspots)

    agents_path = Path.join([output_dir, ".opencode", "AGENTS.md"])
    claude_path = Path.join([output_dir, ".claude", "CLAUDE.md"])

    File.mkdir_p!(Path.dirname(agents_path))
    File.mkdir_p!(Path.dirname(claude_path))

    File.write!(agents_path, briefing)

    File.write!(
      claude_path,
      briefing <> "\n## Rutas\nArtefactos en `../.code-intel/` si existen.\n"
    )

    IO.puts("Generado:\n  #{agents_path}\n  #{claude_path}")
  end

  defp get_stats(project) do
    %{
      files:
        Repo.one(from(f in Schema.File, where: f.project_id == ^project.id, select: count(f.id))),
      symbols:
        Repo.one(
          from(s in Schema.Symbol, where: s.project_id == ^project.id, select: count(s.id))
        ),
      todos:
        Repo.one(
          from(s in Schema.Symbol,
            where: s.project_id == ^project.id,
            where: fragment("? ~* ?", s.content, "TODO|FIXME|HACK"),
            select: count(s.id)
          )
        )
    }
  end

  defp get_hotspots(project) do
    Repo.all(
      from(f in Schema.File,
        where: f.project_id == ^project.id and f.risk_score > 5,
        order_by: [desc: f.risk_score],
        limit: 5,
        select: %{path: f.path, risk: f.risk_score}
      )
    )
  end

  defp generate_briefing(project, stats, hotspots) do
    hot_list =
      Enum.map(hotspots, &"- `#{&1.path}` (risk: #{Float.round(&1.risk, 1)})") |> Enum.join("\n")

    """
    # #{project.name}

    > Generado por Delfos v#{Delfos.version()} — #{DateTime.utc_now() |> DateTime.to_iso8601()}

    ## Proyecto

    | Campo | Valor |
    |-------|-------|
    | Nombre | #{project.name} |
    | Stack | #{project.primary_stack} |
    | Archivos | #{stats.files} |
    | Símbolos | #{stats.symbols} |
    | TODOs/FIXMEs | #{stats.todos} |
    | Último scan | #{project.last_scanned} |

    ## Hotspots (archivos de alto riesgo)

    #{if hot_list == "", do: "- (ninguno)", else: hot_list}

    ## Consultas disponibles

    ```bash
    delfos query "tu búsqueda"
    delfos audit
    delfos explain NombreModulo
    delfos graph callers NombreFuncion
    ```

    ## Reglas de trabajo

    1. Lee los hotspots antes de modificar esos archivos.
    2. Cambios atómicos: un PR, una intención.
    3. Tests para lógica de negocio nueva o modificada.
    """
  end
end
