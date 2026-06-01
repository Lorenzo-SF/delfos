defmodule Delfos.CLI.Commands.Status do
  @moduledoc "Muestra el estado del índice y los proyectos registrados."

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(_args) do
    projects = Repo.all(from(p in Schema.Project, order_by: [desc: p.last_scanned]))

    IO.puts("\n=== DELFOS STATUS ===")
    IO.puts("Proyectos indexados: #{length(projects)}\n")

    if Enum.empty?(projects) do
      IO.puts("  (ninguno — ejecuta: delfos init)")
    else
      Enum.each(projects, &print_project/1)
    end

    IO.puts("")
  end

  defp print_project(p) do
    files =
      Repo.one(from(f in Schema.File, where: f.project_id == ^p.id, select: count(f.id))) || 0

    total_sym =
      Repo.one(from(s in Schema.Symbol, where: s.project_id == ^p.id, select: count(s.id))) || 0

    with_emb =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^p.id and not is_nil(s.embedding),
          select: count(s.id)
        )
      ) || 0

    with_summary =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^p.id and not is_nil(s.summary),
          select: count(s.id)
        )
      ) || 0

    chunks =
      Repo.one(from(c in Schema.Chunk, where: c.project_id == ^p.id, select: count(c.id))) || 0

    cycles =
      Repo.one(
        from(m in Schema.FileMetrics,
          where: m.project_id == ^p.id and m.in_cycle == true,
          select: count(m.id)
        )
      ) || 0

    emb_pct = pct(with_emb, total_sym)
    sum_pct = pct(with_summary, total_sym)

    IO.puts("  ┌ #{p.name}  [#{p.primary_stack}]")
    IO.puts("  │ #{p.path}")
    IO.puts("  │ Branch: #{p.git_branch || "—"}  Commit: #{p.last_commit || "—"}")
    IO.puts("  │")
    IO.puts("  │ Archivos:   #{files}")
    IO.puts("  │ Símbolos:   #{total_sym}  (#{emb_pct}% embebidos, #{sum_pct}% resumidos)")
    IO.puts("  │ Chunks:     #{chunks}")
    IO.puts("  │ Ciclos:     #{if cycles > 0, do: "⚠️  #{cycles}", else: "✓ ninguno"}")
    IO.puts("  └ Último scan: #{p.last_scanned || "nunca"}")
    IO.puts("")
  end

  defp pct(_part, 0), do: 0
  defp pct(part, total), do: Float.round(part / total * 100, 1)
end
