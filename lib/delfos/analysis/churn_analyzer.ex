defmodule Delfos.Analysis.ChurnAnalyzer do
  @moduledoc """
  Analyzes git history to compute per-file risk scores.

  `risk_score = churn * (1 + log(num_authors))` — penalises files with
  many commits AND many distinct authors.

  The `git log` invocation goes through `Arrea.Command.execute/2`, which
  gives us timeout-aware shell execution, telemetry, and consistent
  error handling — no more hand-rolled `Task.async` + `Task.yield`.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}
  alias Delfos.Config.Manager

  @git_log_timeout 60_000

  def analyze(project) do
    max_commits = Manager.analysis()[:churn_max_commits] || 1000

    case Arrea.Command.execute(
           "git log --name-only --format=COMMIT:%an --no-merges --max-count=#{max_commits}",
           cd: project.path,
           timeout: @git_log_timeout
         ) do
      {:ok, %{exit_code: 0, stdout: output}} ->
        stats = parse_log(output)
        persist_stats(stats, project)
        Logger.info("Churn analyzed: #{map_size(stats)} files")

      {:ok, %{exit_code: code, stdout: err}} ->
        Logger.warning("git log exited with #{code}: #{String.slice(err || "", 0, 100)}")

      {:error, :timeout} ->
        Logger.warning("git log timed out after #{@git_log_timeout}ms")

      {:error, reason} ->
        Logger.warning("git log failed: #{inspect(reason)}")
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
