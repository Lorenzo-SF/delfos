defmodule Delfos.Analysis.CouplingAnalyzer do
  @moduledoc """
  Calcula métricas de acoplamiento a partir del grafo de relaciones.

  Métricas calculadas por archivo:
  - afferent_coupling (Ca): cuántos otros archivos dependen de éste.
  - efferent_coupling (Ce): cuántos archivos depende éste.
  - instability: Ce / (Ca + Ce) — 0 = estable, 1 = inestable.
  - debt_score: heurístico de deuda técnica.
  - todo_count: número de TODOs/FIXMEs en los símbolos del archivo.
  - complexity_score: ratio líneas / símbolos como proxy de complejidad.

  La detección de ciclos (in_cycle) la realiza GraphBuilder.detect_and_mark_cycles/1
  que corre inmediatamente después del scan; este módulo no la duplica.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  def analyze(project) do
    Logger.info("Calculando métricas de coupling...")

    files = Repo.all(from(f in Schema.File, where: f.project_id == ^project.id))

    Enum.each(files, fn file ->
      afferent =
        Repo.one(
          from(r in Schema.Relationship,
            join: s in Schema.Symbol,
            on: s.id == r.to_id,
            where: s.file_id == ^file.id and r.project_id == ^project.id,
            select: count(fragment("DISTINCT ?", r.from_id))
          )
        ) || 0

      efferent =
        Repo.one(
          from(r in Schema.Relationship,
            join: s in Schema.Symbol,
            on: s.id == r.from_id,
            where: s.file_id == ^file.id and r.project_id == ^project.id,
            select: count(fragment("DISTINCT ?", r.to_id))
          )
        ) || 0

      total = afferent + efferent
      instability = if total > 0, do: efferent / total, else: 0.0

      todo_count =
        Repo.one(
          from(s in Schema.Symbol,
            where: s.file_id == ^file.id,
            where: fragment("? ~* ?", s.content, "TODO|FIXME|HACK|BUG|DEBT"),
            select: count(s.id)
          )
        ) || 0

      symbol_count =
        Repo.one(from(s in Schema.Symbol, where: s.file_id == ^file.id, select: count(s.id))) || 1

      complexity_score = if symbol_count > 0, do: (file.line_count || 0) / symbol_count, else: 0.0

      debt_score =
        afferent + efferent +
          (if instability > 0.7, do: 5, else: 0) +
          todo_count * 2

      attrs = %{
        file_id: file.id,
        project_id: project.id,
        afferent_coupling: afferent,
        efferent_coupling: efferent,
        instability: instability,
        todo_count: todo_count,
        complexity_score: complexity_score / 1.0,
        debt_score: debt_score / 1.0
        # in_cycle lo gestiona GraphBuilder.detect_and_mark_cycles/1
      }

      case Repo.get_by(Schema.FileMetrics, file_id: file.id) do
        nil ->
          Repo.insert!(Schema.FileMetrics.changeset(%Schema.FileMetrics{}, attrs))

        existing ->
          # Preservar in_cycle si ya fue marcado por GraphBuilder
          Repo.update!(Schema.FileMetrics.changeset(existing, attrs))
      end
    end)

    Logger.info("Coupling calculado para #{length(files)} archivos")
  end
end
