defmodule Delfos.CLI.Commands.Query do
  @moduledoc """
  Hybrid search (vector + BM25 + graph) on the index.

  Output is rendered through `Alaja`. In JSON mode the raw result
  list is emitted without icon prefixes (machine-readable).
  """

  import Ecto.Query
  alias Alaja
  alias Delfos.Syntax.Utils, as: SyntaxUtils
  alias Delfos.{Repo, Schema}
  alias Delfos.Retrieval.HybridSearch
  alias Delfos.Config.Manager

  @help """
  USAGE
      delfos query <text> [flags]

  Hybrid search: vector + BM25 + graph with Reciprocal Rank Fusion.

  ARGUMENTS
      text                Search query (required)

  FLAGS
      --kind <K>          Filter by kind: function | module | class | struct |
                          interface | enum | type
      --level <L>         Search level: symbol | chunk | summary
                          (default: chunk)
      -n <N>              Number of results (default: from config retrieval.final_k)
      --format json       Machine-readable JSON output

  EXAMPLES
      delfos query "JWT authentication"
      delfos query "create user" --kind function
      delfos query "cache invalidation" -n 3 --format json
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  def run_with_opts(%{help: true}) do
    Alaja.print_raw(help_text())
  end

  def run_with_opts(opts) do
    kind = Map.get(opts, :kind)
    level = Map.get(opts, :level)
    n = Map.get(opts, :n)
    format = Map.get(opts, :format)
    rest = Map.get(opts, :rest, [])

    query = Enum.join([Map.get(opts, :text, "") | rest], " ")

    if query == "" do
      Alaja.print_error("Usage: delfos query <text>")
      System.halt(1)
    end

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Alaja.print_error("No projects indexed.")
      System.halt(1)
    end

    k = n || Manager.retrieval()[:final_k] || 7

    parsed_level =
      case level do
        "symbol" -> :symbol
        "summary" -> :summary
        _ -> nil
      end

    case HybridSearch.search(project.id, query,
           k: k * 4,
           final_k: k,
           kind: kind,
           level: parsed_level
         ) do
      {:ok, []} ->
        Alaja.print_warning("No results for: \"#{query}\"")

      {:ok, results} ->
        render_results(query, results, format)
    end
  end

  defp render_results(_query, results, "json") do
    Alaja.print_raw(Jason.encode!(results) <> "\n")
  end

  defp render_results(query, results, _format) do
    Alaja.print_info("\"#{query}\" — #{length(results)} results")
    Alaja.print_raw("\n")

    Enum.each(results, fn r ->
      score = Float.round(r[:combined_score] || 0.0, 3)
      Alaja.print_raw("#{score}  #{r[:kind] || "chunk"}  #{r[:name] || ""}\n")

      if r[:file_path] do
        location =
          "#{r[:file_path]}#{(r[:line_start] && ":#{r[:line_start]}") || ""}"

        Alaja.print_raw("       #{location}\n")
      end

      raw_content = r[:content] || r[:summary] || ""

      if raw_content != "" do
        # Summaries are prose — don't try to highlight them. Chunk / symbol
        # results carry source code we can colour.
        should_highlight = (r[:kind] || "chunk") != "summary"

        rendered_preview =
          if should_highlight do
            preview =
              raw_content
              |> String.slice(0, 200)
              |> String.replace("\n", " ")

            lang = SyntaxUtils.detect_lang_atom(r)

            # Only attempt ANSI highlighting when stdout is a TTY.
            # When output is piped or captured, ANSI escapes can
            # crash :io.put_chars/2 with 'ArgumentError: argument
            # error' (Bug #1 in alaja's printer when the source
            # content has certain Unicode characters).
            if tty?() do
              try do
                Alaja.Syntax.highlight_ansi(preview, lang)
              rescue
                _ -> preview
              end
            else
              preview
            end
          else
            raw_content |> String.slice(0, 200) |> String.replace("\n", " ")
          end

        Alaja.print_raw("       ")
        Alaja.print_raw(rendered_preview)
        Alaja.print_raw("\n")
      end
    end)
  end

  @doc false
  defdelegate detect_lang_atom(r), to: SyntaxUtils

  defp tty? do
    case :io.getopts(:standard_io) do
      {:ok, opts} -> Keyword.get(opts, :tty, false)
      _ -> false
    end
  end
end
