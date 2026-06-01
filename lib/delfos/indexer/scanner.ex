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
      rel = Path.relative_to(path, project.path)

      case File.read(path) do
        {:ok, content} ->
          hash = FileProcessor.compute_hash(content)
          Map.get(existing, rel) != hash

        _ ->
          false
      end
    end)
  end

  defp in_ignored_dir?(path, ignore_dirs) do
    parts = Path.split(path)
    Enum.any?(ignore_dirs, &(&1 in parts))
  end
end
