defmodule Delfos.Indexer.GraphBuilder do
  @moduledoc """
  Builds the dependency graph for an indexed project and detects cycles
  (Tarjan SCC).

  Graph sources:
  - Elixir: `mix xref graph --format dot` (writes to disk, not stdout)
  - TypeScript/JS/Python: regex over indexed file contents
  - Elixir fallback: regex `alias`/`import`/`use`

  NOTE on `mix xref`:
  `mix xref` writes `xref_graph.dot` into the project directory, not
  stdout. It can also fail with an OTP mismatch if the project was
  compiled with a different OTP version — in which case the regex
  fallback is automatic.

  All external commands (mix xref, asdf which, mise which) are routed
  through `Arrea.Command.execute/2` for consistent timeout + telemetry.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  # mix xref can hang on large projects without a timeout
  @xref_timeout 60_000
  # asdf/mise which — local file ops, should be fast
  @resolver_timeout 5_000

  def build(project) do
    Logger.info("Building dependency graph...")

    case project.primary_stack do
      "elixir" ->
        build_elixir_graph(project)

      s when s in ["typescript", "node"] ->
        build_import_graph(project, :typescript)

      "python" ->
        build_import_graph(project, :python)

      _ ->
        Logger.info("Graph: stack #{project.primary_stack} uses regex fallback")
        build_import_graph(project, :generic)
    end

    detect_and_mark_cycles(project)
  end

  # ---------------------------------------------------------------------------
  # Elixir — mix xref writes to disk
  # ---------------------------------------------------------------------------

  defp build_elixir_graph(project) do
    dot_file = Path.join(project.path, "xref_graph.dot")

    mix_bin = resolve_mix_bin(project.path)

    case Arrea.Command.execute(
           "#{mix_bin} xref graph --format dot",
           cd: project.path,
           timeout: @xref_timeout
         ) do
      {:ok, %{exit_code: 0} = result} ->
        if is_file_fresh?(dot_file) do
          case File.read(dot_file) do
            {:ok, dot} ->
              edges = parse_dot(dot)
              Logger.info("#{length(edges)} edges (mix xref)")
              persist_edges(edges, project, "imports")

            _ ->
              Logger.warning("xref_graph.dot not found, falling back to regex")
              build_import_graph(project, :elixir_regex)
          end
        else
          Logger.info("xref_graph.dot fresh, skipping mix xref")
          :ok
        end

      {:ok, %{exit_code: code, stdout: err}} ->
        Logger.warning(
          "mix xref exited #{code} (possible OTP mismatch), falling back to regex. Output: #{String.slice(err || "", 0, 100)}"
        )

        build_import_graph(project, :elixir_regex)

      {:error, :timeout} ->
        Logger.warning("mix xref timed out after #{@xref_timeout}ms, falling back to regex")
        build_import_graph(project, :elixir_regex)

      {:error, reason} ->
        Logger.warning("mix xref failed (#{inspect(reason)}), falling back to regex")
        build_import_graph(project, :elixir_regex)
    end
  end

  defp is_file_fresh?(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} ->
        # Fresh if modified in the last 60 seconds
        :calendar.datetime_to_gregorian_seconds(mtime) >
          :calendar.datetime_to_gregorian_seconds(:calendar.local_time()) - 60

      _ ->
        false
    end
  end

  # Picks `mix` (or the resolved absolute path under asdf/mise) for the
  # given project. Short-circuits to plain `mix` when no version-manager
  # config files exist.
  defp resolve_mix_bin(project_path) do
    tool_versions = Path.join(project_path, ".tool-versions")
    mise_toml = Path.join(project_path, ".mise.toml")

    cond do
      File.exists?(tool_versions) ->
        case resolve_via("asdf", project_path) do
          path when is_binary(path) -> path
          _ -> "mix"
        end

      File.exists?(mise_toml) ->
        case resolve_via("mise", project_path) do
          path when is_binary(path) -> path
          _ -> "mix"
        end

      true ->
        "mix"
    end
  end

  defp resolve_via(tool, project_path) do
    case Arrea.Command.execute("#{tool} which mix", cd: project_path, timeout: @resolver_timeout) do
      {:ok, %{exit_code: 0, stdout: path}} -> String.trim(path)
      _ -> nil
    end
  end

  defp parse_dot(dot) do
    Regex.scan(~r/"([^"]+)"\s+->\s+"([^"]+)"/, dot)
    |> Enum.map(fn [_, from, to] -> {from, to} end)
  end

  # ---------------------------------------------------------------------------
  # Import graph by regex
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

    Logger.info("#{length(edges)} edges (#{mode})")
    persist_edges(edges, project, "imports")
  end

  defp extract_imports(content, :typescript) do
    Regex.scan(~r/(?:import[^"']*|require\s*\()['"](.*?)['"]/, content)
    |> Enum.map(fn [_, m] -> m end)
    |> Enum.reject(&String.starts_with?(&1, "@"))
  end

  defp extract_imports(content, :python) do
    Regex.scan(~r/^(?:from\s+([\w.]+)\s+import|import\s+([\w.]+))/m, content)
    |> Enum.flat_map(fn
      [_, "", m] -> [m]
      [_, m, ""] -> [m]
      _ -> []
    end)
  end

  defp extract_imports(content, :generic) do
    Regex.scan(~r/(?:import|require|use)\s+["']?([\w.\/]+)["']?/, content)
    |> Enum.map(fn [_, m] -> m end)
  end

  # Elixir fallback: alias Foo.Bar, import Foo.Bar, use Foo.Bar
  defp extract_imports(content, :elixir_regex) do
    Regex.scan(~r/^\s*(?:alias|import|use)\s+([\w.]+)/m, content)
    |> Enum.map(fn [_, m] -> m end)
  end

  # ---------------------------------------------------------------------------
  # Persistence + cycle detection
  # ---------------------------------------------------------------------------

  defp persist_edges(edges, project, kind) do
    Enum.each(edges, fn {from_path, to_module} ->
      from_file =
        Repo.one(
          from(f in Schema.File, where: f.project_id == ^project.id and f.path == ^from_path)
        )

      to_file =
        Repo.one(
          from(f in Schema.File, where: f.project_id == ^project.id and f.path == ^to_module)
        )

      cond do
        is_nil(from_file) or is_nil(to_file) ->
          :skip

        from_file.id == to_file.id ->
          :skip

        true ->
          Repo.insert_all(
            Schema.Relationship,
            [
              %{
                project_id: project.id,
                from_id: from_file.id,
                to_id: to_file.id,
                kind: kind,
                inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
                updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
              }
            ],
            on_conflict: :nothing
          )
      end
    end)
  end

  defp detect_and_mark_cycles(project) do
    edges =
      Repo.all(
        from(r in Schema.Relationship,
          where: r.project_id == ^project.id,
          select: {r.from_id, r.to_id}
        )
      )

    cycles = tarjan_scc(edges)
    cycle_file_ids = cycles |> Enum.filter(&(length(&1) > 1)) |> List.flatten() |> Enum.uniq()

    if cycle_file_ids == [] do
      Logger.info("No cycles detected")
    else
      Logger.warning("#{length(cycle_file_ids)} files in dependency cycles")

      Repo.update_all(
        from(m in Schema.FileMetrics, where: m.file_id in ^cycle_file_ids),
        set: [in_cycle: true]
      )
    end
  end

  # Tarjan's strongly connected components algorithm.
  defp tarjan_scc(edges) do
    graph =
      Enum.reduce(edges, %{}, fn {from, to}, acc -> Map.update(acc, from, [to], &[to | &1]) end)

    Enum.reduce(Map.keys(graph), {[], %{}}, fn node, {stack, indices} ->
      if Map.has_key?(indices, node) do
        {stack, indices}
      else
        {new_stack, new_indices, _} =
          strongconnect(node, graph, [node], Map.put(indices, node, 0), %{})

        {new_stack ++ stack, new_indices}
      end
    end)
    |> elem(0)
  end

  defp strongconnect(node, graph, stack, indices, lowlinks) do
    lowlinks = Map.put(lowlinks, node, Map.get(indices, node))
    successors = Map.get(graph, node, [])

    {stack, indices, lowlinks} =
      Enum.reduce(successors, {stack, indices, lowlinks}, fn succ, {s, i, l} ->
        cond do
          not Map.has_key?(i, succ) ->
            {new_s, new_i, new_l} =
              strongconnect(succ, graph, [succ | s], Map.put(i, succ, map_size(i)), l)

            {new_s, new_i,
             Map.update(new_l, node, Map.get(new_i, node), &min(&1, Map.get(new_l, succ)))}

          succ in s ->
            {s, i, Map.update(l, node, Map.get(i, node), &min(&1, Map.get(i, succ)))}

          true ->
            {s, i, l}
        end
      end)

    if Map.get(lowlinks, node) == Map.get(indices, node) do
      {component, new_stack} =
        Enum.take_while(stack, fn n -> n != node end)
        |> then(&{&1 ++ [node], Enum.drop(stack, length(&1) + 1)})

      {[component | Enum.drop(new_stack, length(new_stack))], indices, lowlinks}
    else
      {stack, indices, lowlinks}
    end
  end
end
