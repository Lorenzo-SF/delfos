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

    # PE-3: pre-cargar TODOS los files del proyecto en un mapa UNA sola
    # vez. Antes, build_elixir_graph (mix xref path) hacía hasta 2
    # queries POR edge para resolver from/to files. Para 1000 edges
    # = 2000 queries. Con files_by_path: 0 queries extra en
    # persist_edges/4.
    files_by_path =
      project.id
      |> files_in_project_query()
      |> Repo.all()
      |> Map.new(fn f -> {f.path, f} end)

    case project.primary_stack do
      "elixir" ->
        build_elixir_graph(project, files_by_path)

      s when s in ["typescript", "node"] ->
        build_import_graph(project, :typescript, files_by_path)

      "python" ->
        build_import_graph(project, :python, files_by_path)

      _ ->
        Logger.info("Graph: stack #{project.primary_stack} uses regex fallback")
        build_import_graph(project, :generic, files_by_path)
    end

    detect_and_mark_cycles(project)
  end

  defp files_in_project_query(project_id) do
    from(f in Schema.File, where: f.project_id == ^project_id)
  end

  # ---------------------------------------------------------------------------
  # Elixir — mix xref writes to disk
  # ---------------------------------------------------------------------------

  defp build_elixir_graph(project, files_by_path) do
    dot_file = Path.join(project.path, "xref_graph.dot")

    mix_bin = resolve_mix_bin(project.path)

    case Arrea.Command.execute(
           "#{mix_bin} xref graph --format dot",
           cd: project.path,
           timeout: @xref_timeout
         ) do
      {:ok, %{exit_code: 0}} ->
        if is_file_fresh?(dot_file) do
          case File.read(dot_file) do
            {:ok, dot} ->
              edges = parse_dot(dot)
              Logger.info("#{length(edges)} edges (mix xref)")

              # mix xref genera paths RELATIVOS al project.path
              # (e.g. "lib/delfos/schema/chunk.ex"). El File table
              # guarda paths ABSOLUTOS. Normalizamos a absolutos
              # antes de pasarlos a persist_edges/4 para que el
              # lookup Repo.one(... path == ^abs) matchee.
              #
              # Usamos kind = "imports_file" porque la tabla
              # relationships tiene ahora FKs duales (symbol_id +
              # file_id). Sin este discriminador, persist_edges/4
              # usaría from_id=file_uuid lo que sería semánticamente
              # incorrecto (aunque ahora también nullable).
              abs_edges =
                Enum.map(edges, fn {from, to} ->
                  {absolutize(project.path, from), absolutize(project.path, to)}
                end)

              persist_edges(abs_edges, project, "imports_file", files_by_path)

            _ ->
              Logger.warning("xref_graph.dot not found, falling back to regex")
              build_import_graph(project, :elixir_regex, files_by_path)
          end
        else
          Logger.info("xref_graph.dot fresh, skipping mix xref")
          :ok
        end

      {:ok, %{exit_code: code, stdout: err}} ->
        Logger.warning(
          "mix xref exited #{code} (possible OTP mismatch), falling back to regex. Output: #{String.slice(err || "", 0, 100)}"
        )

        build_import_graph(project, :elixir_regex, files_by_path)

      {:error, :timeout} ->
        Logger.warning("mix xref timed out after #{@xref_timeout}ms, falling back to regex")
        build_import_graph(project, :elixir_regex, files_by_path)

      {:error, reason} ->
        Logger.warning("mix xref failed (#{inspect(reason)}), falling back to regex")
        build_import_graph(project, :elixir_regex, files_by_path)
    end
  end

  defp is_file_fresh?(path) do
    # Fresh si mtime está en los últimos 60 segundos.
    #
    # Bug pre-existente: la versión anterior usaba
    # `:calendar.local_time()` (naive local time) para comparar con
    # el mtime de File.stat (que en Erlang/OTP 24+ es UTC). En zonas
    # horarias distintas de UTC (e.g. CEST = UTC+2), la diferencia
    # era siempre ~7200 segundos, así que el archivo NUNCA se
    # consideraba fresh → se saltaba el parseo de xref → la tabla
    # relationships quedaba vacía para proyectos Elixir.
    #
    # Mi primer fix usaba `DateTime.compare/2` pensando que era como
    # en otros lenguajes, pero esa función NO EXISTE en Elixir
    # (el compilador emitía un warning de "typing violation" pero
    # el código compilaba y devolvía siempre `false` por el disjoint
    # type check del BEAM). El correcto es `DateTime.diff/3` que
    # devuelve la diferencia en la unidad especificada (default
    # :second).
    case File.stat(path) do
      {:ok, %{mtime: mtime}} ->
        mtime_dt = mtime_to_utc_datetime(mtime)
        diff = DateTime.diff(DateTime.utc_now(), mtime_dt, :second)
        diff >= 0 and diff < 60

      _ ->
        false
    end
  end

  # Convierte el mtime que devuelve File.stat (tuple {{y,m,d},{h,m,s}}
  # o NaiveDateTime) a DateTime en UTC. File.stat/1 en Erlang/OTP 24+
  # retorna un NaiveDateTime sin zona, que asumimos es UTC (es lo que
  # devuelve `File.stat` para POSIX timestamps).
  defp mtime_to_utc_datetime({{_, _, _}, {_, _, _}} = mtime) do
    naive = NaiveDateTime.from_erl!(mtime)
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp mtime_to_utc_datetime(%NaiveDateTime{} = naive) do
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp mtime_to_utc_datetime(%DateTime{} = dt), do: dt

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

  # Convierte un path relativo (como sale de mix xref) a absoluto
  # usando el project.path como base. Si el path ya es absoluto,
  # lo devuelve sin cambios.
  defp absolutize(project_path, rel_path) do
    cond do
      Path.type(rel_path) == :absolute -> rel_path
      true -> Path.join(project_path, rel_path)
    end
  end

  # ---------------------------------------------------------------------------
  # Import graph by regex
  # ---------------------------------------------------------------------------

  defp build_import_graph(project, mode, files_by_path) do
    files = Map.values(files_by_path)

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
    persist_edges(edges, project, "imports", files_by_path)
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

  # PE-3: una sola Repo.insert_all batch para todos los edges.
  # Antes: N queries (una por edge) con lookup de from_file/to_file
  # en cada una (otras 2N queries). Total: hasta 3N queries.
  # Ahora: 1 query batch + 1 query pre-carga files (en build/1).
  # Total: 2 queries.
  defp persist_edges(edges, project, kind, files_by_path) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    use_file_ids = kind == "imports_file"

    rows =
      Enum.flat_map(edges, fn {from_path, to_path} ->
        from_file = Map.get(files_by_path, from_path)
        to_file = Map.get(files_by_path, to_path)

        cond do
          is_nil(from_file) or is_nil(to_file) ->
            []

          from_file.id == to_file.id ->
            []

          true ->
            [
              %{
                project_id: project.id,
                from_id: if(use_file_ids, do: nil, else: from_file.id),
                to_id: if(use_file_ids, do: nil, else: to_file.id),
                from_file_id: if(use_file_ids, do: from_file.id, else: nil),
                to_file_id: if(use_file_ids, do: to_file.id, else: nil),
                kind: kind,
                inserted_at: now,
                updated_at: now
              }
            ]
        end
      end)

    if rows == [] do
      :ok
    else
      Repo.insert_all(Schema.Relationship, rows, on_conflict: :nothing)
    end
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
