defmodule Delfos.CLI.Commands.Query do
  @moduledoc "Búsqueda híbrida (vector+BM25+grafo) en el índice."

  import Ecto.Query
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

    if query == "",
      do:
        (
          IO.puts("Uso: delfos query <texto>")
          System.halt(1)
        )

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project,
      do:
        (
          IO.puts("No hay proyectos indexados.")
          System.halt(1)
        )

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
        IO.puts("Sin resultados para: \"#{query}\"")

      {:ok, results} ->
        if opts[:format] == "json" do
          IO.puts(Jason.encode!(results))
        else
          IO.puts("\"#{query}\" — #{length(results)} resultados\n")

          Enum.each(results, fn r ->
            score = Float.round(r[:combined_score] || 0.0, 3)
            IO.puts("#{score}  #{r[:kind] || "chunk"}  #{r[:name] || ""}")

            if r[:file_path],
              do:
                IO.puts(
                  "       #{r[:file_path]}#{(r[:line_start] && ":#{r[:line_start]}") || ""}"
                )

            preview =
              (r[:content] || r[:summary] || "")
              |> String.slice(0, 200)
              |> String.replace("\n", " ")

            IO.puts("       #{preview}\n")
          end)
        end

      {:error, r} ->
        IO.puts("Error: #{inspect(r)}")
    end
  end
end
