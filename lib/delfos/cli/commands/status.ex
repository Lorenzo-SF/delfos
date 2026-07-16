defmodule Delfos.CLI.Commands.Status do
  @moduledoc """
  Shows the status of the index and registered projects.

  Output is rendered through `Alaja` and wrapped in a
  `Alaja.Components.Box` with the title "Delfos Project Status". Each
  section (Projects / Index / DB / Embeddings) is visually separated
  by a `Separator`. The "Last scan" timestamp is color-coded using a
  `ColorWheel`-style indicator: green for < 1h, yellow for 1h-24h,
  red for > 24h.

  The legacy `delfos stadistics` command was absorbed into
  `--stats` in v2.3.0; this module is the single source of truth.
  """

  import Ecto.Query
  alias Alaja
  alias Alaja.Components.{Box, Separator}
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
        # --stats still uses the legacy freeform layout because the
        # per-project stats card is wide and doesn't fit a single
        # box nicely. Future v2.6 could split each project into its
        # own box.
        Enum.each(projects, &print_project_stats/1)

      true ->
        render_status_box(projects)
    end
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

  # ── Box layout (v2.5.0) ──────────────────────────────────────────────────

  # Top-level wrapper. Emits:
  #   ╭─ Delfos Project Status ─────────────╮
  #   │ Projects (1)                       │
  #   │   ─── delfos ──                    │
  #   │   stack:  elixir                   │
  #   │   path:   /home/.../delfos        │
  #   │   ...                             │
  #   │   Last scan: 2h ago  (yellow)     │
  #   │   ───                              │
  #   │ Index                            │
  #   │   Files:      247                │
  #   │   Symbols:    1,420 (12.3% embedded, 5.6% summarised)
  #   │   ...                             │
  #   ╰────────────────────────────────────╯
  defp render_status_box(projects) do
    projects_section = render_projects_section(projects)
    index_section = render_index_section(projects)
    db_section = render_db_section()
    embeddings_section = render_embeddings_section(projects)

    sections =
      [projects_section, index_section, db_section, embeddings_section]
      |> Enum.reject(&(&1 == ""))

    content = Enum.join(sections, "\n")

    Box.print(content,
      title: "Delfos Project Status",
      border: :rounded,
      border_color: {0, 180, 216},
      padding: 1
    )

    Alaja.print_raw("\n")
  end

  defp render_projects_section([]) do
    Alaja.ANSI.fg(220, 180, 0) <>
      "(no projects registered — run: delfos init)\n" <>
      Alaja.ANSI.reset()
  end

  defp render_projects_section(projects) do
    header = "#{Alaja.ANSI.bold_on()}Projects (#{length(projects)})#{Alaja.ANSI.reset()}"
    cards = projects |> Enum.map(&render_project_card/1) |> Enum.join("\n")
    header <> "\n" <> cards
  end

  # Renders one project as a mini-card inside the box. Each line is
  # left-aligned to the box's interior column.
  defp render_project_card(p) do
    last_scan = format_last_scan(p.last_scanned)

    lines = [
      Separator.render(" #{p.name} ", width: 60, color: {100, 100, 100})
      |> Alaja.Buffer.to_iodata()
      |> IO.iodata_to_binary(),
      "  stack:    #{p.primary_stack}",
      "  path:     #{p.path}",
      "  branch:   #{p.git_branch || "—"}",
      "  commit:   #{p.last_commit || "—"}",
      "  last scan: " <> last_scan
    ]

    Enum.join(lines, "\n")
  end

  # Section: KB totals across all projects (when >1) or the single
  # project (when 1).
  defp render_index_section([]), do: ""

  defp render_index_section([project]) do
    header = "#{Alaja.ANSI.bold_on()}Index — #{project.name}#{Alaja.ANSI.reset()}"
    counts = project_counts(project)

    lines = [
      header,
      "  files:     #{counts.files}",
      "  symbols:   #{counts.symbols}  (#{counts.emb_pct}% embedded, #{counts.sum_pct}% summarised)",
      "  chunks:    #{counts.chunks}"
    ]

    cycles_line =
      if counts.cycles > 0 do
        "  cycles:    #{Alaja.ANSI.fg(220, 50, 50)}#{counts.cycles} ⚠#{Alaja.ANSI.reset()}"
      else
        "  cycles:    #{Alaja.ANSI.fg(0, 200, 80)}none#{Alaja.ANSI.reset()}"
      end

    Enum.join(lines ++ [cycles_line], "\n")
  end

  defp render_index_section(projects) do
    header =
      "#{Alaja.ANSI.bold_on()}Index (across #{length(projects)} projects)#{Alaja.ANSI.reset()}"

    totals =
      projects
      |> Enum.map(&project_counts/1)
      |> Enum.reduce(
        %{files: 0, symbols: 0, chunks: 0, with_emb: 0, with_summary: 0, cycles: 0},
        fn c, acc ->
          %{
            files: acc.files + c.files,
            symbols: acc.symbols + c.symbols,
            chunks: acc.chunks + c.chunks,
            with_emb: acc.with_emb + c.with_emb,
            with_summary: acc.with_summary + c.with_summary,
            cycles: acc.cycles + c.cycles
          }
        end
      )

    emb_pct = pct(totals.with_emb, totals.symbols)
    sum_pct = pct(totals.with_summary, totals.symbols)

    lines = [
      header,
      "  files:     #{totals.files}",
      "  symbols:   #{totals.symbols}  (#{emb_pct}% embedded, #{sum_pct}% summarised)",
      "  chunks:    #{totals.chunks}",
      "  cycles:    #{totals.cycles}"
    ]

    Enum.join(lines, "\n")
  end

  defp render_db_section do
    header = "#{Alaja.ANSI.bold_on()}Database#{Alaja.ANSI.reset()}"

    case probe_db() do
      :ok ->
        Enum.join(
          [header, "  status:    #{Alaja.ANSI.fg(0, 200, 80)}connected#{Alaja.ANSI.reset()}"],
          "\n"
        )

      {:error, reason} ->
        Enum.join(
          [
            header,
            "  status:    #{Alaja.ANSI.fg(220, 50, 50)}unreachable#{Alaja.ANSI.reset()}  (#{reason})"
          ],
          "\n"
        )
    end
  end

  defp render_embeddings_section([]), do: ""

  defp render_embeddings_section(projects) do
    header = "#{Alaja.ANSI.bold_on()}Embeddings coverage#{Alaja.ANSI.reset()}"

    rows =
      Enum.map(projects, fn p ->
        c = project_counts(p)
        pct_val = pct(c.with_emb, c.symbols)
        color = coverage_color(pct_val)

        # v2.6.0: render a visual progress bar via Alaja.Components.Bar
        # instead of just a percentage. Width 20 chars fits inside
        # the Box; the colour reflects the same bucket as the
        # percentage (green >=80, yellow >=30, red below).
        buf =
          Alaja.Components.Bar.render(pct_val, 100,
            label: p.name,
            width: 20,
            filled_color: color,
            empty_color: {50, 50, 50},
            show_percent: true
          )

        # Alaja.Components.Bar uses white spaces by default — we
        # need to indent by 2 to align with the rest of the section.
        buf
        |> Alaja.Buffer.to_iodata()
        |> IO.iodata_to_binary()
        |> String.replace(~r/^/, "  ")
      end)

    Enum.join([header | rows], "\n")
  end

  # ── Last scan timestamp + color (UX8 / ColorWheel) ──────────────────────

  # Returns "never" when nil, else "<n>h ago" / "<n>m ago" with an
  # ANSI color prefix matching the freshness bucket:
  #   green  : < 1h
  #   yellow : 1h .. 24h
  #   red    : > 24h
  @doc false
  def format_last_scan(nil), do: "#{Alaja.ANSI.fg(100, 100, 100)}never#{Alaja.ANSI.reset()}"

  def format_last_scan(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt)
    {label, color} = freshness(seconds)

    "#{Alaja.ANSI.fg(elem(color, 0), elem(color, 1), elem(color, 2))}#{label}#{Alaja.ANSI.reset()}"
  end

  # Strings expected by the project.last_scanned field. Defensive: we
  # don't know the exact wire format (DB may store a string via
  # naive_datetime or a DateTime), so handle both.
  def format_last_scan(other) when is_binary(other) do
    case DateTime.from_iso8601(other) do
      {:ok, dt, _} -> format_last_scan(dt)
      _ -> "#{Alaja.ANSI.fg(100, 100, 100)}#{other}#{Alaja.ANSI.reset()}"
    end
  end

  def format_last_scan(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> format_last_scan()
  end

  defp freshness(seconds) when seconds < 60, do: {"just now", {0, 200, 80}}
  defp freshness(seconds) when seconds < 3_600, do: {"#{div(seconds, 60)}m ago", {0, 200, 80}}

  defp freshness(seconds) when seconds < 86_400,
    do: {"#{div(seconds, 3_600)}h ago", {220, 180, 0}}

  defp freshness(seconds), do: {"#{div(seconds, 86_400)}d ago", {220, 50, 50}}

  # Maps a % value to a (r, g, b) tuple. Uses the same palette as the
  # ColorWheel defaults but cheap enough to call inline (no PNG render,
  # no terminal-cap detection — just ANSI truecolor).
  @green {0, 200, 80}
  @yellow {220, 180, 0}
  @red {220, 50, 50}

  defp coverage_color(pct) when pct >= 80, do: @green
  defp coverage_color(pct) when pct >= 30, do: @yellow
  defp coverage_color(_), do: @red

  # ── Per-project aggregates (cached in a small struct to avoid
  #    recomputing across sections) ─────────────────────────────────────

  defp project_counts(p) do
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

    %{
      files: files,
      symbols: total_sym,
      chunks: chunks,
      with_emb: with_emb,
      with_summary: with_summary,
      cycles: cycles,
      emb_pct: pct(with_emb, total_sym),
      sum_pct: pct(with_summary, total_sym)
    }
  end

  defp pct(_part, 0), do: 0.0
  defp pct(part, total), do: Float.round(part / total * 100, 1)

  # ── DB probe ──────────────────────────────────────────────────────────

  defp probe_db do
    Ecto.Adapters.SQL.query(Delfos.Repo, "SELECT 1", [])
    :ok
  rescue
    e -> {:error, Exception.message(e)}
  catch
    _, reason -> {:error, inspect(reason)}
  end

  # ── Legacy --stats path ────────────────────────────────────────────────

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
end
