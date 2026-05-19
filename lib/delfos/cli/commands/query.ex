defmodule Delfos.CLI.Commands.Query do
  @moduledoc "Búsqueda híbrida en el índice de Delfos."

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.Retrieval.HybridSearch

  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        switches: [kind: :string, file: :string, top: :integer, format: :string, level: :string],
        aliases: [n: :top, f: :file, k: :kind]
      )

    query = Enum.join(rest, " ")

    if query == "" do
      IO.puts(
        "Uso: delfos query <texto> [--kind function] [--level summary|symbol|chunk] [-n 10]"
      )

      System.halt(1)
    end

    project = current_project()
    top_n = opts[:top] || 5
    kind = opts[:kind]
    format = opts[:format] || "pretty"

    level =
      case opts[:level] do
        "summary" -> :summary
        "symbol" -> :symbol
        "chunk" -> :chunk
        _ -> nil
      end

    IO.puts("Buscando: \"#{query}\"...")

    case HybridSearch.search(project.id, query,
           k: top_n * 4,
           final_k: top_n,
           kind: kind,
           level: level
         ) do
      {:ok, results} ->
        case format do
          "json" -> IO.puts(Jason.encode!(results))
          _ -> print_results(results, query)
        end

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp print_results([], query) do
    IO.puts("\nSin resultados para: \"#{query}\"")
  end

  defp print_results(results, query) do
    IO.puts("\n#{String.duplicate("─", 60)}")
    IO.puts("Top #{length(results)} resultados para: \"#{query}\"")
    IO.puts(String.duplicate("─", 60))

    Enum.each(Enum.with_index(results, 1), fn {r, i} ->
      score = Float.round(r[:combined_score] || 0.0, 3)
      filled = trunc(score * 20)
      bar = String.duplicate("█", filled) <> String.duplicate("░", 20 - filled)

      IO.puts("\n[#{i}] #{bar} #{score}")
      if r[:name] && r[:name] != "", do: IO.puts("    Nombre:  #{r[:name]}")
      if r[:kind], do: IO.puts("    Tipo:    #{r[:kind]}")

      if r[:content] do
        preview = r[:content] |> String.slice(0, 200) |> String.replace("\n", " ")
        IO.puts("    Preview: #{preview}")
      end
    end)

    IO.puts("")
  end

  defp current_project do
    path = File.cwd!()

    case Repo.get_by(Schema.Project, path: path) ||
           Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1)) do
      nil ->
        IO.puts("No hay proyectos indexados. Ejecuta: delfos init")
        System.halt(1)

      p ->
        p
    end
  end
end
