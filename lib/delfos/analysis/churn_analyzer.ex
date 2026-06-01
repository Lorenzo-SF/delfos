defmodule Delfos.Analysis.ChurnAnalyzer do
  @moduledoc """
  Analiza el historial git para calcular riesgo por archivo.

  risk_score = churn * (1 + log(num_authors))
  Penaliza archivos con muchos commits Y muchos autores distintos.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}
  alias Delfos.Config.Manager

  def analyze(project) do
    max_commits = Manager.analysis()[:churn_max_commits] || 1000

    case System.cmd(
           "git",
           [
             "-C",
             project.path,
             "log",
             "--name-only",
             "--format=COMMIT:%an",
             "--no-merges",
             "--max-count=#{max_commits}"
           ], stderr_to_stdout: true) do
      {output, 0} ->
        stats = parse_log(output)
        persist_stats(stats, project)
        Logger.info("Churn analizado: #{map_size(stats)} archivos")

      {err, _} ->
        Logger.warning("git log falló: #{String.slice(err, 0, 100)}")
    end
  end

  defp parse_log(output) do
    output
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, fn line, {stats, author} ->
      cond do
        String.starts_with?(line, "COMMIT:") ->
          {stats, String.slice(line, 7..-1//1)}

        String.trim(line) != "" and author != nil ->
          path = String.trim(line)

          updated =
            Map.update(stats, path, %{churn: 1, authors: [author]}, fn s ->
              %{churn: s.churn + 1, authors: [author | s.authors]}
            end)

          {updated, author}

        true ->
          {stats, author}
      end
    end)
    |> elem(0)
  end

  defp persist_stats(stats, project) do
    Enum.each(stats, fn {path, %{churn: churn, authors: authors}} ->
      unique_authors = Enum.uniq(authors)
      risk = churn * (1 + :math.log(max(length(unique_authors), 1)))

      Repo.update_all(
        from(f in Schema.File,
          where:
            f.project_id == ^project.id and
              (f.path == ^path or f.path == ^Path.relative_to(path, project.path))
        ),
        set: [git_churn: churn, git_authors: unique_authors, risk_score: risk]
      )
    end)
  end
end
