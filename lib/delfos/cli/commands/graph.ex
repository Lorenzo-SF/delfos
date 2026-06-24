defmodule Delfos.CLI.Commands.Graph do

  alias Alaja
  @moduledoc """
  Consultas al grafo de dependencias.

  Subcomandos:
    callers <nombre>   — qué símbolos llaman a éste
    callees <nombre>   — qué símbolos llama éste
    impact <nombre>    — análisis de impacto BFS (qué se rompe si cambia)
    cycles             — lista todos los archivos en ciclos de dependencia
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(["callers", name | _]) do
    project = current_project()
    symbol = find_symbol(project, name)

    callers =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.from_id,
          join: f in Schema.File,
          on: f.id == s.file_id,
          where: r.to_id == ^symbol.id,
          select: %{name: s.qualified_name, kind: s.kind, file: f.path, line: s.line_start}
        )
      )

    Alaja.print_info("\nSimbolos que llaman a #{symbol.qualified_name}:")

    if Enum.empty?(callers) do
      Alaja.print_info("  (ninguno encontrado — puede ser un entry point)")
    else
      Enum.each(callers, fn c ->
        Alaja.print_info("  #{c.name} (#{c.kind})  →  #{c.file}:#{c.line}")
      end)
    end
  end

  def run(["callees", name | _]) do
    project = current_project()
    symbol = find_symbol(project, name)

    callees =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.to_id,
          join: f in Schema.File,
          on: f.id == s.file_id,
          where: r.from_id == ^symbol.id,
          select: %{name: s.qualified_name, kind: s.kind, file: f.path, line: s.line_start}
        )
      )

    Alaja.print_info("\nSimbolos que llama #{symbol.qualified_name}:")

    if Enum.empty?(callees) do
      Alaja.print_info("  (ninguno encontrado — símbolo hoja)")
    else
      Enum.each(callees, fn c ->
        Alaja.print_info("  #{c.name} (#{c.kind})  →  #{c.file}:#{c.line}")
      end)
    end
  end

  def run(["impact", name | _]) do
    project = current_project()
    symbol = find_symbol(project, name)

    affected = bfs_impact(symbol.id, project.id, 3, MapSet.new([symbol.id]))

    Alaja.print_info("\nImpacto de cambiar #{symbol.qualified_name} (profundidad 3):")

    if Enum.empty?(affected) do
      Alaja.print_info("  (ningún símbolo afectado directamente)")
    else
      affected
      |> Enum.sort_by(& &1.qualified_name)
      |> Enum.each(fn s ->
        Alaja.print_info("  #{s.qualified_name} (#{s.kind})")
      end)
    end
  end

  def run(["cycles" | _]) do
    project = current_project()

    cycles =
      Repo.all(
        from(m in Schema.FileMetrics,
          join: f in Schema.File,
          on: f.id == m.file_id,
          where: m.project_id == ^project.id and m.in_cycle == true,
          order_by: [desc: m.instability],
          select: %{
            path: f.path,
            instability: m.instability,
            afferent: m.afferent_coupling,
            efferent: m.efferent_coupling
          }
        )
      )

    Alaja.print_info("\nArchivos en ciclos de dependencia:")

    if Enum.empty?(cycles) do
      Alaja.print_success("No cycles detected")
    else
      Alaja.print_warning("#{length(cycles)} files in cycles:")

      Enum.each(cycles, fn c ->
        Alaja.print_raw(
          "  #{c.path}  |  instability: #{fmt(c.instability)}  |  Ca: #{c.afferent}  Ce: #{c.efferent}\n"
        )
      end)
    end
  end

  def run(_) do
    Alaja.print_raw("""

    Usage:
      delfos graph callers <name>     # who calls <name>
      delfos graph callees <name>     # what <name> calls
      delfos graph impact  <name>     # BFS impact analysis
      delfos graph cycles             # files in dependency cycles

    """)
  end

  # ---------------------------------------------------------------------------
  # BFS de impacto con conjunto de visitados (evita bucles infinitos)
  # ---------------------------------------------------------------------------

  defp bfs_impact(_symbol_id, _project_id, 0, _visited), do: []

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

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp current_project do
    Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1)) ||
      (
        Alaja.print_info("No hay proyectos. Usa delfos init")
        System.halt(1)
      )
  end

  defp find_symbol(project, name) do
    Repo.one(
      from(s in Schema.Symbol,
        where: s.project_id == ^project.id,
        where: ilike(s.name, ^"%#{name}%") or ilike(s.qualified_name, ^"%#{name}%"),
        limit: 1
      )
    ) ||
      (
        Alaja.print_info("Símbolo no encontrado: #{name}")
        System.halt(1)
      )
  end

  defp fmt(nil), do: "—"
  defp fmt(n) when is_float(n), do: n |> Float.round(2) |> to_string()
  defp fmt(n), do: to_string(n)
end
