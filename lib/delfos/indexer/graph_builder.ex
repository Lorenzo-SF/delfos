defmodule Delfos.Indexer.GraphBuilder do
  @moduledoc "Construye el grafo de dependencias entre símbolos."
  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  def build(project) do
    Logger.info("Construyendo grafo de dependencias...")

    case project.primary_stack do
      "elixir" -> build_elixir_graph(project)
      _ -> Logger.info("Grafo no implementado para #{project.primary_stack}")
    end
  end

  defp build_elixir_graph(project) do
    # Usar mix xref si está disponible
    case System.cmd("mix", ["xref", "graph", "--format", "dot"],
           cd: project.path,
           stderr_to_stdout: true
         ) do
      {dot_output, 0} -> parse_dot_and_persist(dot_output, project)
      _ -> Logger.warning("mix xref falló, saltando grafo de dependencias")
    end
  end

  defp parse_dot_and_persist(dot, project) do
    edges =
      Regex.scan(~r/"([^"]+)"\s+->\s+"([^"]+)"/, dot)
      |> Enum.map(fn [_, from_name, to_name] -> {from_name, to_name} end)

    Logger.info("#{length(edges)} aristas encontradas en el grafo")

    # Borrar relaciones anteriores del proyecto
    Repo.delete_all(from(r in Schema.Relationship, where: r.project_id == ^project.id))

    # Insertar nuevas
    Enum.each(edges, fn {from_name, to_name} ->
      from_sym = find_symbol(project.id, from_name)
      to_sym = find_symbol(project.id, to_name)

      if from_sym && to_sym do
        attrs = %{
          project_id: project.id,
          from_id: from_sym.id,
          to_id: to_sym.id,
          kind: "imports"
        }

        Repo.insert(Schema.Relationship.changeset(%Schema.Relationship{}, attrs),
          on_conflict: :nothing
        )
      end
    end)
  end

  defp find_symbol(project_id, name) do
    Repo.one(
      from(s in Schema.Symbol,
        where: s.project_id == ^project_id,
        where: s.qualified_name == ^name or s.name == ^name,
        limit: 1
      )
    )
  end
end
