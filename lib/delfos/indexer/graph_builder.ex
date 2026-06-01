defmodule Delfos.Indexer.GraphBuilder do
  @moduledoc """
  Construye el grafo de dependencias y detecta ciclos (Tarjan SCC).

  Fuentes del grafo:
  - Elixir: mix xref graph --format dot (escribe a disco, no stdout)
  - TypeScript/JS/Python: regex de imports sobre el contenido indexado
  - Elixir fallback: regex alias/import/use

  NOTA IMPORTANTE sobre mix xref:
  mix xref escribe el fichero xref_graph.dot en el directorio del proyecto,
  NO a stdout. Además puede fallar con OTP mismatch si el proyecto fue
  compilado con una versión diferente de OTP. En ese caso el fallback
  regex es automático.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  def build(project) do
    Logger.info("Construyendo grafo de dependencias...")

    case project.primary_stack do
      "elixir" ->
        build_elixir_graph(project)

      s when s in ["typescript", "node"] ->
        build_import_graph(project, :typescript)

      "python" ->
        build_import_graph(project, :python)

      _ ->
        Logger.info("Grafo: stack #{project.primary_stack} usa fallback regex")
        build_import_graph(project, :generic)
    end

    detect_and_mark_cycles(project)
  end

  # ---------------------------------------------------------------------------
  # Elixir — mix xref escribe a disco
  # ---------------------------------------------------------------------------

  defp build_elixir_graph(project) do
    dot_file = Path.join(project.path, "xref_graph.dot")

    result =
      System.cmd(
        resolve_mix_bin(project.path),
        ["xref", "graph", "--format", "dot"],
        cd: project.path,
        stderr_to_stdout: true
      )

    case result do
      {output, 0} ->
        if is_file_fresh?(dot_file) do
          case File.read(dot_file) do
            {:ok, dot} ->
              edges = parse_dot(dot)
              Logger.info("#{length(edges)} aristas (mix xref)")
              persist_edges(edges, project, "imports")

            _ ->
              Logger.warning("xref_graph.dot no encontrado, usando regex fallback")
              build_import_graph(project, :elixir_regex)
          end
        else
          Logger.info("xref_graph.dot reciente, saltando mix xref")
          :ok
        end

      _ ->
        Logger.warning("mix xref falló (posible OTP mismatch), usando regex fallback")
        build_import_graph(project, :elixir_regex)
    end
  end

  defp is_file_fresh?(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} ->
        # Fresco si se modificó en los últimos 60 segundos
        :calendar.datetime_to_gregorian_seconds(mtime) >
          :calendar.datetime_to_gregorian_seconds(:calendar.local_time()) - 60

      _ ->
        false
    end
  end

  defp resolve_mix_bin(project_path) do
    tool_versions = Path.join(project_path, ".tool-versions")
    mise_toml = Path.join(project_path, ".mise.toml")

    cond do
      File.exists?(tool_versions) ->
        case System.cmd("asdf", ["which", "mix"], cd: project_path, stderr_to_stdout: true) do
          {path, 0} -> String.trim(path)
          _ -> "mix"
        end

      File.exists?(mise_toml) ->
        case System.cmd("mise", ["which", "mix"], cd: project_path, stderr_to_stdout: true) do
          {path, 0} -> String.trim(path)
          _ -> "mix"
        end

      true ->
        "mix"
    end
  end

  defp parse_dot(dot) do
    Regex.scan(~r/"([^"]+)"\s+->\s+"([^"]+)"/, dot)
    |> Enum.map(fn [_, from, to] -> {from, to} end)
  end

  # ---------------------------------------------------------------------------
  # Import graph por regex
  # ---------------------------------------------------------------------------

  defp build_import_graph(project, mode) do
    files = Repo.all(from(f in Schema.File, where: f.project_id == ^project.id))

    edges =
      Enum.flat_map(files, fn file ->
        abs = Path.join(project.path, file.path)

        case File.read(abs) do
          {:ok, content} ->
            extract_imports(content, mode)
            |> Enum.map(fn imported -> {file.path, imported} end)

          _ ->
            []
        end
      end)

    Logger.info("#{length(edges)} aristas (#{mode})")
    persist_edges(edges, project, "imports")
  end

  defp extract_imports(content, :typescript) do
    Regex.scan(~r/(?:import[^"']*|require\s*\()['"](.*?)['"]/, content)
    |> Enum.map(fn [_, m] -> m end)
    |> Enum.reject(&String.starts_with?(&1, "@"))
  end

  defp extract_imports(content, :python) do
    from_i = Regex.scan(~r/^from\s+([\w.]+)\s+import/m, content) |> Enum.map(fn [_, m] -> m end)
    plain = Regex.scan(~r/^import\s+([\w.]+)/m, content) |> Enum.map(fn [_, m] -> m end)
    from_i ++ plain
  end

  defp extract_imports(content, :elixir_regex) do
    Regex.scan(~r/^\s*(?:alias|import|use)\s+([\w.]+)/, content)
    |> Enum.map(fn [_, m] -> m end)
  end

  defp extract_imports(_content, :generic), do: []

  # ---------------------------------------------------------------------------
  # Persistencia
  # ---------------------------------------------------------------------------

  defp persist_edges(edges, project, kind) do
    Repo.delete_all(from(r in Schema.Relationship, where: r.project_id == ^project.id))

    Enum.each(edges, fn {from_name, to_name} ->
      from_sym = find_symbol(project.id, from_name)
      to_sym = find_symbol(project.id, to_name)

      if from_sym && to_sym do
        Repo.insert(
          Schema.Relationship.changeset(%Schema.Relationship{}, %{
            project_id: project.id,
            from_id: from_sym.id,
            to_id: to_sym.id,
            kind: kind
          }),
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
  # Tarjan SCC (iterativo para evitar stack overflow)
  # ---------------------------------------------------------------------------

  def detect_and_mark_cycles(project) do
    edges =
      Repo.all(
        from(r in Schema.Relationship,
          where: r.project_id == ^project.id,
          select: {r.from_id, r.to_id}
        )
      )

    adj =
      Enum.reduce(edges, %{}, fn {f, t}, acc ->
        Map.update(acc, f, [t], &[t | &1])
      end)

    all_nodes =
      (Map.keys(adj) ++ Enum.map(edges, &elem(&1, 1)))
      |> Enum.uniq()

    sccs = tarjan_scc(all_nodes, adj)

    cyclic_ids =
      sccs
      |> Enum.filter(&(length(&1) > 1))
      |> List.flatten()
      |> MapSet.new()

    if MapSet.size(cyclic_ids) > 0 do
      Logger.info("#{MapSet.size(cyclic_ids)} símbolos en ciclos")

      file_ids =
        Repo.all(
          from(s in Schema.Symbol,
            where: s.id in ^MapSet.to_list(cyclic_ids),
            select: s.file_id,
            distinct: true
          )
        )

      Enum.each(file_ids, fn file_id ->
        case Repo.get_by(Schema.FileMetrics, file_id: file_id) do
          nil ->
            Repo.insert!(%Schema.FileMetrics{
              file_id: file_id,
              project_id: project.id,
              in_cycle: true
            })

          existing ->
            existing
            |> Schema.FileMetrics.changeset(%{in_cycle: true})
            |> Repo.update!()
        end
      end)
    else
      Logger.info("Sin ciclos detectados")
    end
  end

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
      if Map.has_key?(acc.indices, node), do: acc, else: strongconnect(node, adj, acc)
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
        cond do
          not Map.has_key?(acc.indices, w) ->
            acc = strongconnect(w, adj, acc)
            Map.update!(acc, :lowlinks, &Map.put(&1, v, min(acc.lowlinks[v], acc.lowlinks[w])))

          MapSet.member?(acc.on_stack, w) ->
            Map.update!(acc, :lowlinks, &Map.put(&1, v, min(acc.lowlinks[v], acc.indices[w])))

          true ->
            acc
        end
      end)

    if state.lowlinks[v] == state.indices[v] do
      {scc, new_stack} = pop_until(state.stack, v, [])

      state
      |> Map.put(:stack, new_stack)
      |> Map.update!(:on_stack, fn s -> Enum.reduce(scc, s, &MapSet.delete(&2, &1)) end)
      |> Map.update!(:sccs, &[scc | &1])
    else
      state
    end
  end

  defp pop_until([h | t], root, acc) do
    if h == root, do: {[h | acc], t}, else: pop_until(t, root, [h | acc])
  end
end
