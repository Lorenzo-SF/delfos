defmodule Delfos.Analysis.ChurnAnalyzer do
  @moduledoc "Analiza el historial git para calcular riesgo de churn."
  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}

  def analyze(project) do
    Logger.info("Analizando churn git...")

    case System.cmd(
           "git",
           [
             "-C",
             project.path,
             "log",
             "--name-only",
             "--format=COMMIT:%an",
             "--no-merges",
             "--max-count=500"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} -> process_log(output, project)
      {err, _} -> Logger.warning("git log falló: #{err}")
    end
  end

  defp process_log(output, project) do
    {file_changes, file_authors} =
      output
      |> String.split("\n")
      |> Enum.reduce({%{}, %{}, nil}, fn line, {changes, authors, current_author} ->
        cond do
          String.starts_with?(line, "COMMIT:") ->
            author = String.slice(line, 7..-1//1)
            {changes, authors, author}

          String.trim(line) != "" ->
            path = String.trim(line)
            new_changes = Map.update(changes, path, 1, &(&1 + 1))
            new_authors = Map.update(authors, path, [current_author], &[current_author | &1])
            {new_changes, new_authors, current_author}

          true ->
            {changes, authors, current_author}
        end
      end)
      |> then(fn {c, a, _} -> {c, a} end)

    # Actualizar risk_score en la DB
    Enum.each(file_changes, fn {path, churn} ->
      authors = Map.get(file_authors, path, []) |> Enum.uniq()
      risk = churn * (1 + :math.log(max(length(authors), 1)))

      Repo.update_all(
        from(f in Schema.File,
          where: f.project_id == ^project.id and f.path == ^path
        ),
        set: [git_churn: churn, git_authors: authors, risk_score: risk]
      )
    end)

    Logger.info("Churn analizado: #{map_size(file_changes)} archivos")
  end
end
