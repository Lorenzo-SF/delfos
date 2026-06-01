defmodule Delfos.CLI.Commands.Audit do
  @moduledoc "Análisis completo de deuda técnica del proyecto."

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(_args) do
    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      IO.puts("No hay proyectos. Usa delfos init")
      System.halt(1)
    end

    IO.puts("\nDELFOS AUDIT — #{project.name}")
    IO.puts(String.duplicate("━", 50))

    hotspots =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id and f.risk_score > 10.0,
          order_by: [desc: f.risk_score],
          limit: 10,
          select: %{path: f.path, risk: f.risk_score, churn: f.git_churn, authors: f.git_authors}
        )
      )

    # Ciclos — ahora reales gracias a GraphBuilder + Tarjan
    cycles =
      Repo.all(
        from(m in Schema.FileMetrics,
          join: f in Schema.File,
          on: f.id == m.file_id,
          where: m.project_id == ^project.id and m.in_cycle == true,
          order_by: [desc: m.instability],
          select: %{path: f.path, instability: m.instability, efferent: m.efferent_coupling},
          limit: 10
        )
      )

    # Alta deuda técnica
    high_debt =
      Repo.all(
        from(m in Schema.FileMetrics,
          join: f in Schema.File,
          on: f.id == m.file_id,
          where: m.project_id == ^project.id and m.debt_score > 10.0,
          order_by: [desc: m.debt_score],
          limit: 10,
          select: %{
            path: f.path,
            debt: m.debt_score,
            instability: m.instability,
            todos: m.todo_count
          }
        )
      )

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

    # Símbolos sin embedding (fallo en indexación)
    missing_emb =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id and is_nil(s.embedding),
          select: count(s.id)
        )
      )

    total_sym =
      Repo.one(from(s in Schema.Symbol, where: s.project_id == ^project.id, select: count(s.id)))

    print_section("HOTSPOTS (alto riesgo de cambio)", hotspots, fn h ->
      "  #{h.path} | churn: #{h.churn} | autores: #{length(h.authors || [])} | risk: #{fmt(h.risk)}"
    end)

    print_section("CICLOS DE DEPENDENCIA ⚠️", cycles, fn c ->
      "  #{c.path} | instability: #{fmt(c.instability)} | efferent: #{c.efferent}"
    end)

    print_section("ALTA DEUDA TÉCNICA", high_debt, fn d ->
      "  #{d.path} | debt: #{fmt(d.debt)} | instability: #{fmt(d.instability)} | TODOs: #{d.todos}"
    end)

    print_section("FIXME / HACK / DEBT detectados", todos, fn t ->
      "  #{t.file}:#{t.line} — #{t.name}"
    end)

    IO.puts("\nÍNDICE DE CALIDAD")
    IO.puts(String.duplicate("─", 40))

    emb_pct =
      if total_sym > 0,
        do: Float.round((total_sym - missing_emb) / total_sym * 100, 1),
        else: 0.0

    IO.puts("  Símbolos con embedding: #{total_sym - missing_emb}/#{total_sym} (#{emb_pct}%)")

    if missing_emb > 0 do
      IO.puts("  ⚠️  #{missing_emb} símbolos sin embedding — re-escanea con: delfos scan --full")
    end

    IO.puts("")
  end

  defp print_section(title, items, formatter) do
    IO.puts("\n#{title}")
    IO.puts(String.duplicate("─", 40))

    if Enum.empty?(items) do
      IO.puts("  ✓ (ninguno detectado)")
    else
      Enum.each(items, &IO.puts(formatter.(&1)))
    end
  end

  defp fmt(nil), do: "—"
  defp fmt(n) when is_float(n), do: Float.round(n, 2) |> to_string()
  defp fmt(n), do: to_string(n)
end
