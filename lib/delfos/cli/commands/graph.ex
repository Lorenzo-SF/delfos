defmodule Delfos.CLI.Commands.Graph do
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
          where: r.to_id == ^symbol.id,
          select: %{name: s.qualified_name, kind: s.kind, file: s.file_id}
        )
      )

    IO.puts("\nFunciones que llaman a #{symbol.qualified_name}:")
    Enum.each(callers, fn c -> IO.puts("  #{c.name} (#{c.kind})") end)
    if Enum.empty?(callers), do: IO.puts("  (ninguna encontrada)")
  end

  def run(["impact", name | _]) do
    project = current_project()
    symbol = find_symbol(project, name)

    # BFS por el grafo de llamadas
    affected = bfs_impact(symbol.id, project.id, 3)
    IO.puts("\nQué se ve afectado si cambia #{symbol.qualified_name}:")
    Enum.each(affected, fn s -> IO.puts("  #{s.qualified_name} (#{s.kind})") end)
    if Enum.empty?(affected), do: IO.puts("  (ninguno encontrado)")
  end

  def run(_) do
    IO.puts("Uso: delfos graph callers <nombre> | delfos graph impact <nombre>")
  end

  defp bfs_impact(symbol_id, project_id, depth) when depth > 0 do
    direct =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.to_id,
          where: r.from_id == ^symbol_id and r.project_id == ^project_id,
          select: s
        )
      )

    indirect =
      Enum.flat_map(direct, fn s ->
        bfs_impact(s.id, project_id, depth - 1)
      end)

    (direct ++ indirect) |> Enum.uniq_by(& &1.id)
  end

  defp bfs_impact(_, _, 0), do: []

  defp current_project do
    Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1)) ||
      (
        IO.puts("No hay proyectos. Usa delfos init")
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
        IO.puts("Símbolo no encontrado: #{name}")
        System.halt(1)
      )
  end
end
