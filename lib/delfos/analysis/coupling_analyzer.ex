defmodule Delfos.Analysis.CouplingAnalyzer do
  @moduledoc "Calcula métricas de acoplamiento a partir del grafo de relaciones."
  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  def analyze(project) do
    Logger.info("Calculando métricas de coupling...")

    files = Repo.all(from(f in Schema.File, where: f.project_id == ^project.id, select: f.id))

    Enum.each(files, fn file_id ->
      afferent =
        Repo.one(
          from(r in Schema.Relationship,
            join: s in Schema.Symbol,
            on: s.id == r.to_id,
            where: s.file_id == ^file_id and r.project_id == ^project.id,
            select: count(fragment("DISTINCT ?", r.from_id))
          )
        ) || 0

      efferent =
        Repo.one(
          from(r in Schema.Relationship,
            join: s in Schema.Symbol,
            on: s.id == r.from_id,
            where: s.file_id == ^file_id and r.project_id == ^project.id,
            select: count(fragment("DISTINCT ?", r.to_id))
          )
        ) || 0

      total = afferent + efferent
      instability = if total > 0, do: efferent / total, else: 0.0
      debt = afferent + efferent + if instability > 0.7, do: 5, else: 0

      attrs = %{
        file_id: file_id,
        project_id: project.id,
        afferent_coupling: afferent,
        efferent_coupling: efferent,
        instability: instability,
        debt_score: debt / 1.0
      }

      case Repo.get_by(Schema.FileMetrics, file_id: file_id) do
        nil -> Repo.insert!(Schema.FileMetrics.changeset(%Schema.FileMetrics{}, attrs))
        existing -> Repo.update!(Schema.FileMetrics.changeset(existing, attrs))
      end
    end)

    Logger.info("Coupling calculado para #{length(files)} archivos")
  end
end
