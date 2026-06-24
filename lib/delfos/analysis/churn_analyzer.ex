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

  @external_cmd_timeout 60_000

  def analyze(project) do
    max_commits = Manager.analysis()[:churn_max_commits] || 1000

    # A-11 audit fix: git log en repos grandes puede colgarse, usamos timeout.
    case run_external(
           fn ->
             System.cmd(
               "git",
               [
                 "-C",
                 project.path,
                 "log",
                 "--name-only",
                 "--format=COMMIT:%an",
                 "--no-merges",
                 "--max-count=#{max_commits}"
               ],
               stderr_to_stdout: true
             )
           end,
           @external_cmd_timeout
         ) do
      {:ok, {output, 0}} ->
        stats = parse_log(output)
        persist_stats(stats, project)
        Logger.info("Churn analizado: #{map_size(stats)} archivos")

      {:ok, {err, _}} ->
        Logger.warning("git log falló: #{String.slice(err, 0, 100)}")

      {:error, :timeout} ->
        Logger.warning("git log timed out tras #{@external_cmd_timeout}ms")
    end
  end

  # Wrapper con timeout para System.cmd externos. Si tarda demasiado,
  # mata el proceso y devuelve {:error, :timeout}.
  @spec run_external((-> {String.t(), non_neg_integer()}), pos_integer()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, :timeout}
  defp run_external(fun, timeout_ms) when is_function(fun, 0) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      {:exit, _reason} -> {:error, :timeout}
      nil -> {:error, :timeout}
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
