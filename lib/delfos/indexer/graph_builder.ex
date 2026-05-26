defmodule Delfos.Indexer.GraphBuilder do
  @moduledoc """
  Construye el grafo de dependencias con upserts por lote.
  Elimina delete_all + insert. Usa on_conflict para idempotencia.
  Mantiene detección de ciclos (Tarjan SCC).
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

  defp build_elixir_graph(project) do
    dot_path = Path.join(project.path, "xref_graph.dot")
    File.rm(dot_path)

    case System.cmd("mix", ["xref", "graph", "--format", "dot"],
           cd: project.path,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        if File.exists?(dot_path) do
          parse_dot_and_persist(File.read!(dot_path), project)
          File.rm(dot_path)
        else
          Logger.warning("xref_graph.dot no encontrado, fallback regex")
          build_import_graph(project, :elixir_regex)
        end

      {err, _} ->
        Logger.warning("mix xref falló: #{String.slice(err, 0, 120)}, fallback regex")
        build_import_graph(project, :elixir_regex)
    end
  end

  defp parse_dot_and_persist(dot, project) do
    edges =
      Regex.scan(~r/"([^"]+)"\s+->\s+"([^"]+)"/, dot)
      |> Enum.map(fn [_, from_name, to_name] -> {from_name, to_name} end)

    Logger.info("#{length(edges)} aristas encontradas (mix xref)")
    persist_edges(edges, project, "imports")
  end

  defp build_import_graph(project, mode) do
    files = Repo.all(from(f in Schema.File, where: f.project_id == ^project.id))

    edges =
      Enum.flat_map(files, fn file ->
        case File.read(Path.join(project.path, file.path)) do
          {:ok, content} ->
            extract_imports(content, file.path, mode) |> Enum.map(&{file.path, &1})

          _ ->
            []
        end
      end)

    Logger.info("#{length(edges)} aristas encontradas (#{mode})")
    persist_edges(edges, project, "imports")
  end

  defp extract_imports(content, _path, :typescript) do
    Regex.scan(~r/(?:import[^"']*|require\s*\()['"]([^'"]+)['"]/, content)
    |> Enum.map(fn [_, mod] -> mod end)
    |> Enum.reject(&String.starts_with?(&1, "@"))
  end

  defp extract_imports(content, _path, :python) do
    from_imports =
      Regex.scan(~r/^from\s+([\w.]+)\s+import/m, content) |> Enum.map(fn [_, mod] -> mod end)

    plain_imports =
      Regex.scan(~r/^import\s+([\w.]+)/m, content) |> Enum.map(fn [_, mod] -> mod end)

    from_imports ++ plain_imports
  end

  defp extract_imports(content, _path, :elixir_regex) do
    Regex.scan(~r/^\s*(?:alias|import|use)\s+([\w.]+)/, content)
    |> Enum.map(fn [_, mod] -> mod end)
  end

  defp persist_edges(edges, project, kind) do
    valid =
      Enum.reduce(edges, [], fn {from_name, to_name}, acc ->
        from_sym = find_symbol(project.id, from_name)
        to_sym = find_symbol(project.id, to_name)

        if from_sym && to_sym do
          [
            %{
              project_id: project.id,
              from_id: from_sym.id,
              to_id: to_sym.id,
              kind: kind,
              weight: 1.0,
              metadata: %{},
              inserted_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            }
            | acc
          ]
        else
          acc
        end
      end)

    Enum.chunk_every(valid, 500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Schema.Relationship, chunk,
        on_conflict: {:replace, [:weight, :metadata, :updated_at]},
        conflict_target: [:from_id, :to_id, :kind]
      )
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

  def detect_and_mark_cycles(project) do
    Logger.info("Detectando ciclos (Tarjan SCC)...")

    edges =
      Repo.all(
        from(r in Schema.Relationship,
          where: r.project_id == ^project.id,
          select: {r.from_id, r.to_id}
        )
      )

    adj = Enum.reduce(edges, %{}, fn {f, t}, acc -> Map.update(acc, f, [t], &[t | &1]) end)
    all_nodes = (Map.keys(adj) ++ Enum.map(edges, &elem(&1, 1))) |> Enum.uniq()
    sccs = tarjan_scc(all_nodes, adj)
    cyclic = sccs |> Enum.filter(&(length(&1) > 1)) |> List.flatten() |> MapSet.new()

    if MapSet.size(cyclic) > 0 do
      Logger.info("#{MapSet.size(cyclic)} símbolos en ciclos")

      file_ids =
        Repo.all(
          from(s in Schema.Symbol,
            where: s.id in ^MapSet.to_list(cyclic),
            select: distinct(s.file_id)
          )
        )

      Enum.each(file_ids, fn fid ->
        case Repo.get_by(Schema.FileMetrics, file_id: fid) do
          nil ->
            Repo.insert(%Schema.FileMetrics{file_id: fid, project_id: project.id, in_cycle: true})

          m ->
            Repo.update!(Schema.FileMetrics.changeset(m, %{in_cycle: true}))
        end
      end)
    else
      Logger.info("Sin ciclos")
    end
  end

  defp tarjan_scc(nodes, adj) do
    state = %{index: 0, stack: [], on_stack: MapSet.new(), indices: %{}, lowlinks: %{}, sccs: []}

    Enum.reduce(nodes, state, fn n, acc ->
      if Map.has_key?(acc.indices, n), do: acc, else: strongconnect(n, adj, acc)
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

    state =
      Enum.reduce(Map.get(adj, v, []), state, fn w, acc ->
        if not Map.has_key?(acc.indices, w) do
          acc = strongconnect(w, adj, acc)
          Map.update!(acc, :lowlinks, &Map.put(&1, v, min(acc.lowlinks[v], acc.lowlinks[w])))
        else
          if MapSet.member?(acc.on_stack, w) do
            Map.update!(acc, :lowlinks, &Map.put(&1, v, min(acc.lowlinks[v], acc.indices[w])))
          else
            acc
          end
        end
      end)

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
    if head == root, do: {[head | acc], tail}, else: pop_scc(tail, root, [head | acc])
  end
end
