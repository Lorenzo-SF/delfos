defmodule Delfos.Indexer.GraphBuilder do
  @moduledoc """
  Construye el grafo de dependencias entre símbolos y archivos.

  Por stack:
  - Elixir: usa `mix xref graph --format dot` (más preciso).
  - TypeScript/JS: extrae imports mediante regex sobre el contenido de los archivos.
  - Python: extrae imports mediante regex.
  - Otros: sin grafo (sin-ops).

  Tras construir el grafo ejecuta detección de ciclos (Tarjan SCC) y
  marca los archivos involucrados en ciclos en `file_metrics.in_cycle`.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  def build(project) do
    Logger.info("Construyendo grafo de dependencias...")

    case project.primary_stack do
      "elixir" -> build_elixir_graph(project)
      stack when stack in ["typescript", "node"] -> build_import_graph(project, :typescript)
      "python" -> build_import_graph(project, :python)
      _ -> Logger.info("Grafo no implementado para #{project.primary_stack}")
    end

    detect_and_mark_cycles(project)
  end

  # ---------------------------------------------------------------------------
  # Elixir — mix xref
  # ---------------------------------------------------------------------------

  defp build_elixir_graph(project) do
    case System.cmd("mix", ["xref", "graph", "--format", "dot"],
           cd: project.path,
           stderr_to_stdout: true
         ) do
      {dot_output, 0} ->
        parse_dot_and_persist(dot_output, project)

      _ ->
        Logger.warning("mix xref falló, intentando fallback regex para Elixir")
        build_import_graph(project, :elixir_regex)
    end
  end

  defp parse_dot_and_persist(dot, project) do
    edges =
      Regex.scan(~r/"([^"]+)"\s+->\s+"([^"]+)"/, dot)
      |> Enum.map(fn [_, from_name, to_name] -> {from_name, to_name} end)

    Logger.info("#{length(edges)} aristas encontradas en el grafo (mix xref)")
    persist_edges(edges, project, "imports")
  end

  # ---------------------------------------------------------------------------
  # TypeScript / Python / Elixir regex — extracción de imports
  # ---------------------------------------------------------------------------

  defp build_import_graph(project, mode) do
    files = Repo.all(from(f in Schema.File, where: f.project_id == ^project.id))

    edges =
      Enum.flat_map(files, fn file ->
        abs_path = Path.join(project.path, file.path)

        case File.read(abs_path) do
          {:ok, content} ->
            extract_imports(content, file.path, mode)
            |> Enum.map(fn imported -> {file.path, imported} end)

          _ ->
            []
        end
      end)

    Logger.info("#{length(edges)} aristas encontradas en el grafo (#{mode})")
    persist_edges(edges, project, "imports")
  end

  defp extract_imports(content, _path, :typescript) do
    # import ... from './something'  |  require('./something')
    Regex.scan(~r/(?:import[^"']*|require\s*\()['"]([^'"]+)['"]/, content)
    |> Enum.map(fn [_, mod] -> mod end)
    |> Enum.reject(&String.starts_with?(&1, "@"))
  end

  defp extract_imports(content, _path, :python) do
    # from x import y  |  import x
    from_imports =
      Regex.scan(~r/^from\s+([\w.]+)\s+import/m, content)
      |> Enum.map(fn [_, mod] -> mod end)

    plain_imports =
      Regex.scan(~r/^import\s+([\w.]+)/m, content)
      |> Enum.map(fn [_, mod] -> mod end)

    from_imports ++ plain_imports
  end

  defp extract_imports(content, _path, :elixir_regex) do
    # alias X.Y  |  import X.Y  |  use X.Y
    Regex.scan(~r/^\s*(?:alias|import|use)\s+([\w.]+)/, content)
    |> Enum.map(fn [_, mod] -> mod end)
  end

  # ---------------------------------------------------------------------------
  # Persistencia de aristas
  # ---------------------------------------------------------------------------

  defp persist_edges(edges, project, kind) do
    Repo.delete_all(from(r in Schema.Relationship, where: r.project_id == ^project.id))

    Enum.each(edges, fn {from_name, to_name} ->
      from_sym = find_symbol(project.id, from_name)
      to_sym = find_symbol(project.id, to_name)

      if from_sym && to_sym do
        attrs = %{
          project_id: project.id,
          from_id: from_sym.id,
          to_id: to_sym.id,
          kind: kind
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

  # ---------------------------------------------------------------------------
  # Detección de ciclos — Tarjan SCC
  # ---------------------------------------------------------------------------

  @doc """
  Ejecuta el algoritmo de Tarjan sobre el grafo de relaciones del proyecto
  y marca `in_cycle = true` en `file_metrics` para los archivos involucrados.
  """
  def detect_and_mark_cycles(project) do
    Logger.info("Detectando ciclos de dependencia (Tarjan SCC)...")

    # Cargar todas las aristas como {from_symbol_id, to_symbol_id}
    edges =
      Repo.all(
        from(r in Schema.Relationship,
          where: r.project_id == ^project.id,
          select: {r.from_id, r.to_id}
        )
      )

    # Construir mapa de adyacencia symbol_id -> [symbol_id]
    adj =
      Enum.reduce(edges, %{}, fn {from_id, to_id}, acc ->
        Map.update(acc, from_id, [to_id], &[to_id | &1])
      end)

    all_nodes = Map.keys(adj) ++ (Enum.map(edges, &elem(&1, 1)) |> Enum.uniq())
    all_nodes = Enum.uniq(all_nodes)

    sccs = tarjan_scc(all_nodes, adj)

    # SCCs con más de un nodo son ciclos
    cyclic_symbol_ids =
      sccs
      |> Enum.filter(&(length(&1) > 1))
      |> List.flatten()
      |> MapSet.new()

    if MapSet.size(cyclic_symbol_ids) > 0 do
      Logger.info("#{MapSet.size(cyclic_symbol_ids)} símbolos involucrados en ciclos")

      # Encontrar file_ids de esos símbolos
      cyclic_file_ids =
        Repo.all(
          from(s in Schema.Symbol,
            where: s.id in ^MapSet.to_list(cyclic_symbol_ids),
            select: s.file_id,
            distinct: true
          )
        )

      # Marcar in_cycle = true en file_metrics
      Enum.each(cyclic_file_ids, fn file_id ->
        case Repo.get_by(Schema.FileMetrics, file_id: file_id) do
          nil ->
            Repo.insert(%Schema.FileMetrics{
              file_id: file_id,
              project_id: project.id,
              in_cycle: true
            })

          existing ->
            existing
            |> Schema.FileMetrics.changeset(%{in_cycle: true})
            |> Repo.update()
        end
      end)
    else
      Logger.info("No se detectaron ciclos")
    end
  end

  # ---------------------------------------------------------------------------
  # Algoritmo de Tarjan (SCC iterativo para evitar stack overflow)
  # ---------------------------------------------------------------------------

  defp tarjan_scc(nodes, adj) do
    state = %{
      index: 0,
      stack: [],
      on_stack: MapSet.new(),
      indices: %{},
      lowlinks: %{},
      sccs: []
    }

    Enum.reduce(nodes, state, fn node, acc ->
      if Map.has_key?(acc.indices, node) do
        acc
      else
        strongconnect(node, adj, acc)
      end
    end).sccs
  end

  defp strongconnect(v, adj, state) do
    state =
      state
      |> Map.update!(:indices, &Map.put(&1, v, state.index))
      |> Map.update!(:lowlinks, &Map.put(&1, v, state.index))
      |> Map.update!(:index, &(&1 + 1))
      |> Map.update!(:stack, &[v | &1])
      |> Map.update!(:on_stack, &MapSet.put(&1, v))

    neighbors = Map.get(adj, v, [])

    state =
      Enum.reduce(neighbors, state, fn w, acc ->
        if not Map.has_key?(acc.indices, w) do
          acc = strongconnect(w, adj, acc)
          new_low = min(acc.lowlinks[v], acc.lowlinks[w])
          Map.update!(acc, :lowlinks, &Map.put(&1, v, new_low))
        else
          if MapSet.member?(acc.on_stack, w) do
            new_low = min(acc.lowlinks[v], acc.indices[w])
            Map.update!(acc, :lowlinks, &Map.put(&1, v, new_low))
          else
            acc
          end
        end
      end)

    # Si v es raíz de un SCC, extraer el componente
    if state.lowlinks[v] == state.indices[v] do
      {scc, new_stack} = pop_scc(state.stack, v, [])

      state
      |> Map.put(:stack, new_stack)
      |> Map.update!(:on_stack, fn s -> Enum.reduce(scc, s, &MapSet.delete(&2, &1)) end)
      |> Map.update!(:sccs, &[scc | &1])
    else
      state
    end
  end

  defp pop_scc([head | tail], root, acc) do
    if head == root do
      {[head | acc], tail}
    else
      pop_scc(tail, root, [head | acc])
    end
  end
end
