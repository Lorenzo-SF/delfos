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

  PE-2: antes hacía 5 queries POR archivo (5N queries totales). Ahora
  son 3 queries agregadas con GROUP BY, sin importar cuántos archivos
  haya. Para 1000 archivos: 5000 queries → 3 queries.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  def analyze(project) do
    Logger.info("Calculando métricas de coupling...")

    file_ids =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id,
          select: f.id
        )
      )

    case file_ids do
      [] ->
        :ok

      _ ->
        ca_per_file = afferent_per_file(project.id, file_ids)
        ce_per_file = efferent_per_file(project.id, file_ids)
        symbols_per_file = symbols_per_file(project.id, file_ids)
        line_counts = line_counts_per_file(project.id, file_ids)

        now =
          DateTime.utc_now()
          |> DateTime.truncate(:second)

        attrs_per_file =
          Enum.map(file_ids, fn file_id ->
            afferent = Map.get(ca_per_file, file_id, 0)
            efferent = Map.get(ce_per_file, file_id, 0)
            total = afferent + efferent
            instability = if total > 0, do: efferent / total, else: 0.0
            sym_count = max(Map.get(symbols_per_file, file_id, 0), 1)
            todos = Map.get(symbols_per_file, :todos, %{}) |> Map.get(file_id, 0)
            lines = Map.get(line_counts, file_id, 0)
            complexity = lines / sym_count

            debt_score =
              afferent + efferent + if(instability > 0.7, do: 5, else: 0) + todos * 2

            %{
              file_id: file_id,
              project_id: project.id,
              afferent_coupling: afferent,
              efferent_coupling: efferent,
              instability: instability,
              todo_count: todos,
              complexity_score: complexity,
              debt_score: debt_score,
              updated_at: now
              # in_cycle lo gestiona GraphBuilder.detect_and_mark_cycles/1
            }
          end)

        upsert_file_metrics(attrs_per_file)

        Logger.info("Coupling calculado para #{length(file_ids)} archivos")
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Queries agregadas (PE-2)
  # ---------------------------------------------------------------------------

  # Ca por file: para cada archivo, cuántos DISTINTOS símbolos lo
  # "apuntan" (relaciones donde s.file_id == X y r.to_id == s.id).
  # GROUP BY file_id → una fila por archivo.
  defp afferent_per_file(project_id, file_ids) do
    Repo.all(
      from(s in Schema.Symbol,
        join: r in Schema.Relationship,
        on: r.to_id == s.id,
        where: s.file_id in ^file_ids and r.project_id == ^project_id,
        group_by: s.file_id,
        select: {s.file_id, count(fragment("DISTINCT ?", r.from_id))}
      )
    )
    |> Map.new()
  end

  # Ce por file: para cada archivo, cuántos DISTINTOS símbolos "salen".
  defp efferent_per_file(project_id, file_ids) do
    Repo.all(
      from(s in Schema.Symbol,
        join: r in Schema.Relationship,
        on: r.from_id == s.id,
        where: s.file_id in ^file_ids and r.project_id == ^project_id,
        group_by: s.file_id,
        select: {s.file_id, count(fragment("DISTINCT ?", r.to_id))}
      )
    )
    |> Map.new()
  end

  # Símbolos por file + TODOs por file (en una sola query con FILTER).
  # Devuelve %{file_id => total_symbols, :todos => %{file_id => todo_count}}.
  defp symbols_per_file(_project_id, file_ids) do
    rows =
      Repo.all(
        from(s in Schema.Symbol,
          where: s.file_id in ^file_ids,
          group_by: s.file_id,
          select: %{
            file_id: s.file_id,
            total: count(s.id),
            todos:
              count(
                fragment(
                  "? ~* 'TODO|FIXME|HACK|BUG|DEBT'",
                  s.content
                )
              )
          }
        )
      )

    totals =
      rows
      |> Enum.map(fn r -> {r.file_id, r.total} end)
      |> Map.new()

    todos =
      rows
      |> Enum.map(fn r -> {r.file_id, r.todos} end)
      |> Map.new()

    Map.merge(totals, %{todos: todos})
  end

  defp line_counts_per_file(_project_id, file_ids) do
    Repo.all(
      from(f in Schema.File,
        where: f.id in ^file_ids,
        select: {f.id, f.line_count}
      )
    )
    |> Enum.map(fn {id, lc} -> {id, lc || 0} end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Batch upsert
  # ---------------------------------------------------------------------------

  # Inserta/actualiza FileMetrics para todos los archivos en una sola
  # operación. on_conflict preserva `in_cycle` que pudo marcar GraphBuilder.
  defp upsert_file_metrics(attrs_per_file) do
    Repo.insert_all(
      Schema.FileMetrics,
      attrs_per_file,
      on_conflict:
        {:replace,
         [
           :afferent_coupling,
           :efferent_coupling,
           :instability,
           :todo_count,
           :complexity_score,
           :debt_score,
           :updated_at
         ]},
      conflict_target: [:file_id]
    )
  end
end
