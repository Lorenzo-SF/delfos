defmodule Delfos.Indexer.Scanner do
  @moduledoc """
  Orquesta el scan completo o incremental de un proyecto.
  Usa Flow para procesar archivos en paralelo.
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

    # 2. Encontrar archivos a procesar
    files_to_process =
      project.path
      |> find_source_files()
      |> maybe_filter_changed(project, full)

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

    # 5. Calcular métricas de coupling
    CouplingAnalyzer.analyze(project)

    # 6. Actualizar last_scanned
    project
    |> Schema.Project.changeset(%{last_scanned: DateTime.utc_now()})
    |> Repo.update!()

    {:ok, %{processed: ok, errors: err}}
  rescue
    e -> {:error, Exception.message(e)}
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

  defp maybe_filter_changed(files, _project, true), do: files

  defp maybe_filter_changed(files, project, false) do
    # Filtrar solo los que cambiaron (comparar content_hash)
    existing =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id,
          select: {f.path, f.content_hash}
        )
      )
      |> Map.new()

    Enum.filter(files, fn path ->
      relative = Path.relative_to(path, project.path)
      hash = compute_hash(path)
      Map.get(existing, relative) != hash
    end)
  end

  defp compute_hash(path) do
    case File.read(path) do
      {:ok, content} -> :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      _ -> nil
    end
  end
end
