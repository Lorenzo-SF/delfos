defmodule Delfos.CLI.Commands.Status do
  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(_args) do
    projects =
      Repo.all(
        from(p in Schema.Project,
          order_by: [desc: p.last_scanned],
          select: %{
            name: p.name,
            path: p.path,
            stack: p.primary_stack,
            last_scanned: p.last_scanned
          }
        )
      )

    IO.puts("\n=== DELFOS STATUS ===")
    IO.puts("Proyectos indexados: #{length(projects)}\n")

    Enum.each(projects, fn p ->
      files =
        Repo.one(
          from(f in Schema.File,
            join: pr in Schema.Project,
            on: pr.id == f.project_id,
            where: pr.path == ^p.path,
            select: count(f.id)
          )
        )

      symbols =
        Repo.one(
          from(s in Schema.Symbol,
            join: pr in Schema.Project,
            on: pr.id == s.project_id,
            where: pr.path == ^p.path,
            select: count(s.id)
          )
        )

      IO.puts("  #{p.name} (#{p.stack})")
      IO.puts("    #{p.path}")
      IO.puts("    #{files} archivos | #{symbols} símbolos | último scan: #{p.last_scanned}")
    end)

    IO.puts("")
  end
end
