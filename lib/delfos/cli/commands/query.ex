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

      {:error, r} ->
        Alaja.print_error("Error: #{inspect(r)}")
    end
  end
end
