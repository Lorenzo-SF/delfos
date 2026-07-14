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
    dirs = if ignore_dirs == [], do: Manager.indexing()[:ignore_dirs] || [], else: ignore_dirs

    # Merge explicit ignore_dirs with patterns from .gitignore, if present.
    # The user's .gitignore is the source of truth for "what not to
    # commit" and usually matches "what not to index" for source code.
    dirs = dirs ++ read_gitignore_patterns(project_path)

    Path.wildcard("#{project_path}/**/*")
    |> Enum.filter(&File.regular?/1)
    |> Enum.filter(&Dispatcher.supported?/1)
    |> Enum.reject(&in_ignored_dir?(&1, dirs))
  end

  @doc """
  Filtra la lista de rutas a solo los archivos que cambiaron desde el último scan.
  Lee el contenido una sola vez y reutiliza el hash en FileProcessor.
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

    Enum.filter(paths, fn path ->
      # f.path is stored as the absolute path, so we compare against
      # `path` directly (not the relative form). Previously this
      # used Path.relative_to/2 which never matched the stored key
      # and forced every file to be re-processed on every scan.
      case File.read(path) do
        {:ok, content} ->
          hash = FileProcessor.compute_hash(content)
          Map.get(existing, path) != hash

        _ ->
          false
      end
    end)
  end

  defp in_ignored_dir?(path, ignore_dirs) do
    # An ignore pattern matches only if it appears as a path
    # segment *after* the project root. Otherwise patterns like
    # "delfos" (the project directory itself) would match every
    # file inside the project — e.g.
    #   "/home/me/delfos/lib/delfos/cli.ex"
    # would have parts ["/", "home", "me", "delfos", "lib", "delfos", "cli.ex"]
    # and `"delfos" in parts` is true, rejecting the file.
    #
    # To fix: find the project root by walking up the path until
    # we find a part whose name matches an ignore pattern, and
    # only consider matches *after* the project root.
    #
    # We can't easily detect the project root from a single path
    # string, so we use a simpler heuristic: a pattern matches
    # only if it's NOT one of the immediate top-level segments of
    # the path. We approximate "top-level" by taking the first
    # 4 path parts (root + a few levels) and excluding any
    # ignore pattern that matches there.
    parts = Path.split(path)

    Enum.any?(ignore_dirs, fn pattern ->
      # Find the last occurrence of `pattern` in parts. If the
      # index is greater than 3 (deeper than 3 levels from root),
      # it's a real match.
      last_idx = last_index_of(parts, pattern)
      last_idx != nil and last_idx >= 3
    end)
  end

  defp last_index_of(list, value) do
    list
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {item, idx} ->
      if item == value, do: Enum.count(list) - 1 - idx, else: nil
    end)
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
