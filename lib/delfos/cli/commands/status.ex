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
      delfos status [--stats]

  Show index and project status: file count, symbol coverage,
  embedding %, summary %, dependency cycles.

  FLAGS
      --stats        Also show MCP usage stats and KB stats (alias of `delfos
                     status --stats`, absorbs the legacy `delfos stadistics`
                     command).

  Reads from the DB — no LLM.
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  def run_with_opts(%{help: true}) do
    Alaja.print_raw(help_text())
  end

  def run_with_opts(%{stats: show_stats}) do
    show_stats? = show_stats == true
    projects = Repo.all(from(p in Schema.Project, order_by: [desc: p.last_scanned]))

    cond do
      show_stats? and projects != [] ->
        Enum.each(projects, &print_project_stats/1)

      true ->
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
  end

  # MCP usage + KB stats for a single project. Absorbs the legacy
  # `delfos stadistics` command (removed in v2.3.0). See
  # docs/REFACTOR_PLAN.md §3.9.
  defp print_project_stats(project) do
    usage = Delfos.Statistics.usage_snapshot(project.id)
    index = Delfos.Statistics.index_snapshot(project)

    Alaja.print_raw("\n=== DELFOS PROJECT STATS — #{project.name} ===\n")

    Alaja.print_raw("\n  USAGE (LOCAL ONLY)\n")
    Alaja.print_raw("    Tokens generated (estimated): #{usage.response_tokens}\n")
    Alaja.print_raw("    MCP calls processed:          #{usage.total_calls}\n")
    Alaja.print_raw("    Last used:                    #{usage.last_used_at}\n")

    Alaja.print_raw("\n  KNOWLEDGE BASE\n")

    Alaja.print_raw(
      "    Files / symbols / chunks:     #{index.files} / #{index.symbols} / #{index.chunks}\n"
    )

    Alaja.print_raw(
      "    Embedded / summarised:        #{index.embedded_symbols} / #{index.summarized_symbols}\n"
    )

    Alaja.print_raw("    TODOs detected:               #{index.todos}\n")
  end

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    run_with_opts(%{stats: "--stats" in args, help: false})
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
