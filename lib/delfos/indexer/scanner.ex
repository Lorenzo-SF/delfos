defmodule Delfos.Indexer.Scanner do
  @moduledoc """
  Orquesta el scan completo o incremental de un proyecto.
  Usa Flow para procesar archivos en paralelo.

  Mejoras:
  - El hash del archivo se calcula una sola vez (ya no se recalcula en FileProcessor).
  - `find_source_files` filtra antes de lanzar Flow para evitar trabajo innecesario.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}
  alias Delfos.Parsers.Dispatcher
  alias Delfos.Indexer.{FileProcessor, GraphBuilder}
  alias Delfos.Analysis.{ChurnAnalyzer, CouplingAnalyzer}

  @ignore_dirs Application.compile_env(:delfos, [:indexing, :ignore_dirs], [])

  def scan(project, opts \\ []) do
    full = Keyword.get(opts, :full, false)

    Logger.info(
      "Iniciando scan de #{project.name} (#{if full, do: "completo", else: "incremental"})"
    )

    # 1. Analizar churn git
    ChurnAnalyzer.analyze(project)

    # 2. Encontrar archivos a procesar (con hashes precalculados)
    files_to_process = find_changed_files(project, full)

    Logger.info("#{length(files_to_process)} archivos a procesar")

    # 3. Procesar en paralelo con Flow
    results =
      files_to_process
      |> Flow.from_enumerable(max_demand: 4)
      |> Flow.map(&FileProcessor.process(&1, project))
      |> Enum.to_list()

    ok = Enum.count(results, &match?({:ok, _}, &1))
    err = Enum.count(results, &match?({:error, _}, &1))
    Logger.info("Scan completado: #{ok} OK, #{err} errores")

    # 4. Reconstruir grafo de dependencias
    GraphBuilder.build(project)

    # 5. Calcular métricas de coupling (incluye detección de ciclos)
    CouplingAnalyzer.analyze(project)

    # 6. Actualizar last_scanned
    project
    |> Schema.Project.changeset(%{last_scanned: DateTime.utc_now()})
    |> Repo.update!()

    {:ok, %{processed: ok, errors: err}}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ---------------------------------------------------------------------------
  # Detección de archivos cambiados — hash calculado una sola vez
  # ---------------------------------------------------------------------------

  defp find_changed_files(project, full) do
    all_files =
      project.path
      |> find_source_files()

    if full do
      all_files
    else
      existing_hashes =
        Repo.all(
          from(f in Schema.File,
            where: f.project_id == ^project.id,
            select: {f.path, f.content_hash}
          )
        )
        |> Map.new()

      Enum.filter(all_files, fn path ->
        relative = Path.relative_to(path, project.path)

        case File.read(path) do
          {:ok, content} ->
            hash = FileProcessor.compute_hash(content)
            Map.get(existing_hashes, relative) != hash

          _ ->
            false
        end
      end)
    end
  end

  defp find_source_files(path) do
    Path.wildcard("#{path}/**/*")
    |> Enum.filter(&File.regular?/1)
    |> Enum.filter(&Dispatcher.supported?/1)
    |> Enum.reject(&in_ignored_dir?/1)
  end

  defp in_ignored_dir?(path) do
    Enum.any?(@ignore_dirs, &String.contains?(path, "/#{&1}/"))
  end
end
