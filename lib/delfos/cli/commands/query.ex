defmodule Delfos.CLI.Commands.Query do
  @moduledoc """
  Hybrid search (vector + BM25 + graph) on the index.

  Output is rendered through `Alaja`. In JSON mode the raw result
  list is emitted without icon prefixes (machine-readable).
  """

  import Ecto.Query
  alias Alaja
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

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        switches: [kind: :string, level: :string, n: :integer, format: :string],
        aliases: [n: :n]
      )

    query = Enum.join(rest, " ")

    if query == "" do
      Alaja.print_error("Usage: delfos query <text>")
      System.halt(1)
    end

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Alaja.print_error("No projects indexed.")
      System.halt(1)
    end

    k = opts[:n] || Manager.retrieval()[:final_k] || 7
    kind = opts[:kind]

    level =
      case opts[:level] do
        "symbol" -> :symbol
        "summary" -> :summary
        _ -> nil
      end

    case HybridSearch.search(project.id, query, k: k * 4, final_k: k, kind: kind, level: level) do
      {:ok, []} ->
        Alaja.print_warning("No results for: \"#{query}\"")

      {:ok, results} ->
        if opts[:format] == "json" do
          Alaja.print_raw(Jason.encode!(results) <> "\n")
        else
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

            preview =
              (r[:content] || r[:summary] || "")
              |> String.slice(0, 200)
              |> String.replace("\n", " ")

            Alaja.print_info("       #{preview}\n")
          end)
        end

      {:error, reason} ->
        Alaja.print_error("Search failed: #{format_error(reason)}")

        case reason do
          %Postgrex.Error{} ->
            Alaja.print_info("Hint: is PostgreSQL running? Try `delfos doctor`")

          :no_results ->
            :ok

          _ ->
            Alaja.print_info("Hint: run `delfos doctor` to verify the environment")
        end
    end
  end

  defp format_error(%Postgrex.Error{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)
end
