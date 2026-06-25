defmodule Delfos.CLI.Commands.Status do
  @moduledoc """
  Shows the status of the index and registered projects.

  Output is rendered through `Alaja`. The box-drawing characters
  (┌, │, └) are emitted via `print_raw` because Alaja doesn't
  have a box helper.
  """

  import Ecto.Query
  alias Alaja
  alias Delfos.{Repo, Schema}

  @help """
  USAGE
      delfos status

  Show index and project status: file count, symbol coverage,
  embedding %, summary %, dependency cycles.

  Reads from the DB — no flags.
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(_args) do
    projects = Repo.all(from(p in Schema.Project, order_by: [desc: p.last_scanned]))

    Alaja.print_raw("\n=== DELFOS STATUS ===\n")
    Alaja.print_info("Indexed projects: #{length(projects)}")
    Alaja.print_raw("\n")

    if Enum.empty?(projects) do
      Alaja.print_warning("(none — run: delfos init)")
    else
      Enum.each(projects, &print_project/1)
    end

    Alaja.print_raw("\n")
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

    Alaja.print_info("  ┌ #{p.name}  [#{p.primary_stack}]")
    Alaja.print_info("  │ #{p.path}")
    Alaja.print_raw("  │ Branch: #{p.git_branch || "—"}  Commit: #{p.last_commit || "—"}\n")
    Alaja.print_info("  │")
    Alaja.print_info("  │ Files:      #{files}")

    Alaja.print_info(
      "  │ Symbols:    #{total_sym}  (#{emb_pct}% embedded, #{sum_pct}% summarised)"
    )

    Alaja.print_info("  │ Chunks:     #{chunks}")

    if cycles > 0 do
      Alaja.print_warning("  │ Cycles:     #{cycles}")
    else
      Alaja.print_success("  │ Cycles:     none")
    end

    Alaja.print_raw("  └ Last scan:  #{p.last_scanned || "never"}\n")
    Alaja.print_raw("\n")
  end

  defp pct(_part, 0), do: 0
  defp pct(part, total), do: Float.round(part / total * 100, 1)
end
