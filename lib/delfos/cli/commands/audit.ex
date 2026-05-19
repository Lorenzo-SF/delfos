defmodule Delfos.CLI.Commands.Audit do
  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(_args) do
    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project,
      do:
        (
          IO.puts("No hay proyectos. Usa delfos init")
          System.halt(1)
        )

    IO.puts("\nDELFOS AUDIT — #{project.name}")
    IO.puts(String.duplicate("━", 50))

    # TODOs críticos
    todos =
      Repo.all(
        from(s in Schema.Symbol,
          join: f in Schema.File,
          on: f.id == s.file_id,
          where: s.project_id == ^project.id,
          where: fragment("? ~* ?", s.content, "FIXME|HACK|BUG|DEBT"),
          select: %{file: f.path, name: s.name, line: s.line_start},
          limit: 10
        )
      )

    # Archivos con alto riesgo
    hotspots =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id and f.risk_score > 10,
          order_by: [desc: f.risk_score],
          limit: 10,
          select: %{path: f.path, risk: f.risk_score, churn: f.git_churn, authors: f.git_authors}
        )
      )

    # Métricas de coupling
    cycles =
      Repo.all(
        from(m in Schema.FileMetrics,
          join: f in Schema.File,
          on: f.id == m.file_id,
          where: m.project_id == ^project.id and m.in_cycle == true,
          select: %{path: f.path, instability: m.instability},
          limit: 10
        )
      )

    print_section("HOTSPOTS (alto riesgo de cambio)", hotspots, fn h ->
      "  #{h.path} | churn: #{h.churn} | autores: #{length(h.authors)} | risk: #{Float.round(h.risk, 1)}"
    end)

    print_section("CICLOS DE DEPENDENCIA", cycles, fn c ->
      "  #{c.path} | instability: #{Float.round(c.instability, 2)}"
    end)

    print_section("FIXME / HACK / DEBT detectados", todos, fn t ->
      "  #{t.file}:#{t.line} — #{t.name}"
    end)

    IO.puts("")
  end

  defp print_section(title, items, formatter) do
    IO.puts("\n#{title}")
    IO.puts(String.duplicate("─", 40))

    if Enum.empty?(items) do
      IO.puts("  (ninguno detectado)")
    else
      Enum.each(items, &IO.puts(formatter.(&1)))
    end
  end
end
