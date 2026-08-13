defmodule Delfos.Indexer.Scanner do
  @moduledoc """
  Localiza archivos fuente y detecta cuáles han cambiado (por SHA256).
  El procesado paralelo lo hace FileProcessor vía Arrea.Parallel.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.Parsers.Dispatcher
  alias Delfos.Indexer.FileProcessor
  alias Delfos.Config.Manager

  @doc "Devuelve lista de rutas absolutas de archivos fuente del proyecto."
  def find_files(project_path, ignore_dirs \\ []) do
    project_path
    |> stream_files(ignore_dirs)
    |> Enum.to_list()
  end

  @doc """
  Igual que `find_files/2` pero devuelve un Stream — no materializa la
  lista completa en memoria. PE-1: reemplaza `Path.wildcard` por un
  walk recursivo sobre `File.ls` que filtra y yielda a medida que
  encuentra archivos. En `deps/` de un proyecto Elixir (>50k archivos),
  `Path.wildcard` podía OOM; este Stream es O(1) en memoria.
  """
  @default_max_depth 50
  @default_max_files 500_000

  @spec stream_files(Path.t(), [String.t()]) :: Enumerable.t()
  def stream_files(project_path, ignore_dirs \\ [], opts \\ []) do
    dirs = effective_ignore_dirs(project_path, ignore_dirs)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    max_files = Keyword.get(opts, :max_files, @default_max_files)

    # SE-2/S11: limit depth + total files. The stream itself is bounded
    # in memory (O(1) entries held), but the queue + per-file work can
    # still balloon on pathological FS. A 50-deep tree with symlinks
    # could loop forever; a `node_modules/` with 200k files can melt
    # CPU. We bail out with a warning at the soft caps.
    Stream.resource(
      fn -> {1, 0, [project_path]} end,
      fn
        {_depth, count, []} when count >= max_files ->
          {:halt, []}

        {_depth, _count, []} ->
          {:halt, []}

        {depth, count, [path | rest]} ->
          cond do
            depth > max_depth ->
              log_depth_exceeded(max_depth, project_path)
              {:halt, {depth, count, rest}}

            true ->
              {entries, new_count, new_queue, next_depth} =
                process_path_with_count(path, rest, count, max_files, dirs, project_path, depth)

              {entries, {next_depth, new_count, new_queue}}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp process_path_with_count(path, rest, count, max_files, dirs, project_path, depth) do
    cond do
      File.regular?(path) and not in_ignored_dir?(path, dirs, project_path) and
        Dispatcher.supported?(path) and count < max_files ->
        # Incrementar count DESPUÉS de verificar el límite, para no
        # emitir archivos cuando ya estamos en el cap. depth NO cambia
        # para archivos: solo cambia al descender en un directorio.
        {[path], count + 1, rest, depth}

      File.dir?(path) and not in_ignored_dir?(path, dirs, project_path) ->
        new_paths = list_directory(path)
        # Solo incrementamos depth al descender en un subdirectorio.
        {[], count, rest ++ new_paths, depth + 1}

      true ->
        {[], count, rest, depth}
    end
  end

  defp log_depth_exceeded(max_depth, project_path) do
    require Logger

    Logger.warning(
      "Scanner: max depth #{max_depth} exceeded at #{project_path}. " <>
        "Files deeper than this are not indexed. Increase :max_depth " <>
        "if your project legitimately nests deeper (or add a symlink " <>
        "guard if it's a loop)."
    )
  end

  defp list_directory(path) do
    case File.ls(path) do
      {:ok, entries} ->
        Enum.map(entries, &Path.join(path, &1))

      {:error, reason} ->
        require Logger
        Logger.debug("Scanner: cannot ls #{path}: #{inspect(reason)}")
        []
    end
  end

  # Resuelve la lista efectiva de dirs a ignorar: argumento explícito
  # o config + .gitignore. Extraído para compartir entre find_files y
  # stream_files.
  defp effective_ignore_dirs(project_path, ignore_dirs) do
    base = if ignore_dirs == [], do: Manager.indexing()[:ignore_dirs] || [], else: ignore_dirs
    base ++ read_gitignore_patterns(project_path)
  end

  @doc """
  Filtra la lista de rutas a solo los archivos que cambiaron desde el último scan.

  P3: devuelve `{path, content, hash}` en lugar de solo `path`, para que
  el caller (`FileProcessor.process_file/3`) no tenga que releer
  ni re-hashear. Esto elimina el doble I/O + doble hash que existía
  entre `find_changed_files/2` y `upsert_file/4`.

  El hash se calcula una sola vez aquí y se reutiliza al persistir.
  """
  def find_changed_files(paths, project) do
    existing =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id,
          select: {f.path, f.content_hash}
        )
      )
      |> Map.new()

    for path <- paths,
        {:ok, content} <- [File.read(path)],
        hash = FileProcessor.compute_hash(content),
        Map.get(existing, path) != hash do
      {path, content, hash}
    end
  end

  defp in_ignored_dir?(path, ignore_dirs, project_path) do
    # The semantics of "ignored directory" depend entirely on
    # whether the pattern appears INSIDE the project tree — not in
    # the absolute path prefix and not as the project directory
    # itself. The cleanest way to enforce that is to convert each
    # path to project-relative form BEFORE matching.
    #
    # Concretely, the buggy heuristic previously embedded in
    # `last_index_of/2` was: "pattern at depth ≥ 3 from path root".
    # That worked accidentally for `/home/me/proj/...` layouts (where
    # the project root sits at depth 3, so depth ≥ 3 makes the whole
    # project look like one giant ignored dir) but broke for shorter
    # absolute paths like `/tmp/proj/...` (where the project root is
    # at depth 2 and `tmp` at depth 1 was reported as "depth 3",
    # falsely rejecting every file). Switching to relative-path
    # matching makes both cases work correctly.
    relative =
      case Path.relative_to(path, project_path) do
        rel when is_binary(rel) -> rel
        # Outside the project root (e.g. the project_path itself
        # changed mid-walk). Be safe and reject.
        _ -> ".."
      end

    cond do
      String.starts_with?(relative, "..") ->
        false

      true ->
        rel_parts = Path.split(relative)

        Enum.any?(ignore_dirs, fn pattern ->
          Enum.any?(rel_parts, &(&1 == pattern))
        end)
    end
  end

  # Reads the project's .gitignore and returns a list of directory
  # patterns. We only extract directory-style ignores (e.g. "node_modules",
  # "build/", "**/dist") — file patterns like "*.log" are intentionally
  # ignored because the source-file filter below only walks the
  # filesystem and a stray log file won't waste much.
  #
  # Returns [] if no .gitignore is present or it's not a git repo.
  @doc false
  def read_gitignore_patterns(project_path) do
    gitignore = Path.join(project_path, ".gitignore")

    if File.regular?(gitignore) do
      gitignore
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.flat_map(&parse_pattern/1)
      |> Enum.uniq()
    else
      []
    end
  end

  # Convert one .gitignore line into the directory names we'll match
  # against path parts. We only emit directory-style ignores:
  #
  #   "node_modules"     -> ["node_modules"]
  #   "build/"           -> ["build"]
  #   "**/dist"          -> ["dist"]
  #   "/dist"            -> ["dist"]
  #   "*.log"            -> []      (file pattern, skipped)
  defp parse_pattern(line) do
    cond do
      # Comment / blank already filtered, but be defensive.
      line == "" ->
        []

      String.contains?(line, "*") and not String.contains?(line, "/") ->
        # Bare glob without a slash, e.g. "*.log" — skip, file pattern.
        []

      true ->
        [extract_dirname(line)]
    end
  end

  defp extract_dirname(pattern) do
    # Strip leading "**/" or "/" and trailing "/".
    p =
      pattern
      |> String.replace(~r/^\*\*\//, "")
      |> String.replace(~r/^\//, "")
      |> String.replace(~r/\/$/, "")

    # Take the first path segment as the directory name to match.
    case String.split(p, "/") do
      [first | _] -> first
      [] -> p
    end
  end
end
