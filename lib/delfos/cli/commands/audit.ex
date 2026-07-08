defmodule Delfos.CLI.Commands.Audit do
  @moduledoc """
  Complete technical-debt audit of a project.

  Sections are printed via Alaja so they get coloured headers and
  per-section separators consistent with the rest of the CLI.
  """

  import Ecto.Query
  alias Alaja
  alias Delfos.Syntax.Utils, as: SyntaxUtils
  alias Delfos.{Repo, Schema}

  @help """
  USAGE
      delfos audit [flags]

  Technical-debt audit of the active project.

  FLAGS
      --file <path>     Audit a single file instead of the whole project

  SECTIONS
    HOTSPOTS                Files with high risk score (churn + complexity)
    DEPENDENCY CYCLES       Files in circular import chains
    HIGH TECHNICAL DEBT     Files with high debt score
    FIXME / HACK markers    Symbols containing debt markers
    QUALITY INDEX           % of symbols with embeddings
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  # Legacy argv entry point — kept for backward compat.
  def run(args) when is_list(args), do: run_with_opts(%{})

  @doc """
  Runs audit with pre-parsed options.
  Supports `--file` to scope the audit to a single file path (or
  partial path / basename). When set, the queries filter by file and
  the project-wide headers are still printed but the lists are
  scoped to that file.
  """
  def run_with_opts(opts) do
    file_filter = Map.get(opts, :file)

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Alaja.print_error("No projects registered. Run: delfos init")
      System.halt(1)
    end

    title_suffix = if file_filter, do: " — file: #{file_filter}", else: ""

    Alaja.print_raw("\n")
    Alaja.print_raw(String.duplicate("━", 50) <> "\n")
    Alaja.print_info("DELFOS AUDIT — #{project.name}#{title_suffix}")
    Alaja.print_raw(String.duplicate("━", 50) <> "\n")

    # `f` is the file alias in the queries below; build a path filter
    # pattern that each query can ILIKE against when --file is set.
    # El matching es por substring (parcial), aceptando tanto path
    # completo como basename.
    file_filter_pattern = if file_filter, do: "%#{file_filter}%", else: nil

    hotspots_query =
      from(f in Schema.File,
        where: f.project_id == ^project.id and f.risk_score > 10.0,
        order_by: [desc: f.risk_score],
        limit: 10,
        select: %{path: f.path, risk: f.risk_score, churn: f.git_churn, authors: f.git_authors}
      )

    hotspots_query =
      if file_filter, do: from(f in hotspots_query, where: ilike(f.path, ^file_filter_pattern)), else: hotspots_query

    hotspots = Repo.all(hotspots_query)

    # Real cycles thanks to GraphBuilder + Tarjan SCC
    cycles_query =
      from(m in Schema.FileMetrics,
        join: f in Schema.File,
        on: f.id == m.file_id,
        where: m.project_id == ^project.id and m.in_cycle == true,
        order_by: [desc: m.instability],
        select: %{path: f.path, instability: m.instability, efferent: m.efferent_coupling},
        limit: 10
      )

    cycles_query =
      if file_filter, do: from([_m, f] in cycles_query, where: ilike(f.path, ^file_filter_pattern)), else: cycles_query

    cycles = Repo.all(cycles_query)

    high_debt_query =
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

    high_debt_query =
      if file_filter, do: from([_m, f] in high_debt_query, where: ilike(f.path, ^file_filter_pattern)), else: high_debt_query

    high_debt = Repo.all(high_debt_query)

    # When filtering by file, scope the TODO query to that file too.
    todo_query =
      from(s in Schema.Symbol,
        join: f in Schema.File,
        on: f.id == s.file_id,
        where: s.project_id == ^project.id,
        where: fragment("? ~* ?", s.content, "FIXME|HACK|BUG|DEBT"),
        select: %{
          file: f.path,
          name: s.name,
          line: s.line_start,
          content: s.content,
          language: f.language
        },
        limit: 10
      )

    todo_query =
      if file_filter, do: from([_s, f] in todo_query, where: ilike(f.path, ^file_filter_pattern)), else: todo_query

    todos = Repo.all(todo_query)

    # Symbols without embedding — failed indexing
    missing_emb =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id and is_nil(s.embedding),
          select: count(s.id)
        )
      )

    total_sym =
      Repo.one(from(s in Schema.Symbol, where: s.project_id == ^project.id, select: count(s.id)))

    print_section("HOTSPOTS (high change risk)", hotspots, fn h ->
      "  #{h.path} | churn: #{h.churn} | authors: #{length(h.authors || [])} | risk: #{fmt(h.risk)}"
    end)

    print_section("DEPENDENCY CYCLES", cycles, fn c ->
      "  #{c.path} | instability: #{fmt(c.instability)} | efferent: #{c.efferent}"
    end)

    print_section("HIGH TECHNICAL DEBT", high_debt, fn d ->
      "  #{d.path} | debt: #{fmt(d.debt)} | instability: #{fmt(d.instability)} | TODOs: #{d.todos}"
    end)

    print_section(
      "FIXME / HACK / DEBT markers",
      todos,
      &format_todo/1
    )

    Alaja.print_raw("\n")
    Alaja.print_info("QUALITY INDEX")
    Alaja.print_raw(String.duplicate("─", 40) <> "\n")

    emb_pct =
      if total_sym > 0,
        do: Float.round((total_sym - missing_emb) / total_sym * 100, 1),
        else: 0.0

    Alaja.print_raw(
      "  Symbols with embedding: #{total_sym - missing_emb}/#{total_sym} (#{emb_pct}%)\n"
    )

    if missing_emb > 0 do
      Alaja.print_warning(
        "#{missing_emb} symbols without embedding — re-scan with: delfos scan --full"
      )
    end

    Alaja.print_raw("\n")
  end

  defp print_section(title, items, formatter) do
    Alaja.print_raw("\n" <> title <> "\n")
    Alaja.print_raw(String.duplicate("─", 40) <> "\n")

    if Enum.empty?(items) do
      Alaja.print_success("(none detected)")
    else
      Enum.each(items, &Alaja.print_raw(formatter.(&1) <> "\n"))
    end
  end

  defp fmt(nil), do: "—"
  defp fmt(n) when is_float(n), do: Float.round(n, 2) |> to_string()
  defp fmt(n), do: to_string(n)

  @doc false
  def format_todo(t) do
    header = "  #{t.file}:#{t.line} — #{t.name}"
    snippet = extract_snippet(t.content, t.line)
    lang = SyntaxUtils.safe_to_atom(t.language)

    snippet_lines =
      snippet
      |> String.split("\n")
      |> Enum.map_join("\n", fn line ->
        Alaja.Syntax.highlight_ansi(line, lang) |> IO.iodata_to_binary()
      end)

    header <> "\n" <> snippet_lines
  end

  @doc false
  def extract_snippet(content, line) when is_binary(content) and is_integer(line) and line > 0 do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {_text, n} -> n >= line and n <= line + 1 end)
    |> Enum.map_join("\n", fn {text, _} -> text end)
  end

  def extract_snippet(_, _), do: ""

  @doc false
  defdelegate safe_to_atom(lang), to: SyntaxUtils
end
