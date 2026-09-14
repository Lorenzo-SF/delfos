defmodule Delfos.Analysis.ChurnAnalyzer do
  @moduledoc """
  Analyzes git history to compute per-file risk scores.

  `risk_score = churn * (1 + log(num_authors))` — penalises files with
  many commits AND many distinct authors.

  Delegates git log execution to `Trebejo.Git.Local.churn/2`, which handles
  timeout-aware shell execution via Arrea, telemetry, and consistent
  error handling.
  """

  import Ecto.Query
  require Logger

  alias Delfos.{Repo, Schema}
  alias Delfos.Config.Manager

  @git_log_timeout 60_000

  def analyze(project) do
    max_commits = Manager.analysis()[:churn_max_commits] || 1000

    case safe_churn(project.path,
           max_commits: max_commits,
           no_merges: true,
           include_authors: true,
           timeout: @git_log_timeout
         ) do
      {:ok, stats} ->
        persist_stats(stats, project)
        Logger.info("Churn analyzed: #{length(stats)} files")

      {:error, reason} ->
        Logger.warning("git log failed: #{inspect(reason)}")
    end
  end

  # Safe wrapper around the optional Trebejo dep — returns graceful
  # fallback when the lib is absent (CI without private-repo access).
  defp safe_churn(path, opts) do
    if Code.ensure_loaded?(Trebejo.Git.Local) and
         function_exported?(Trebejo.Git.Local, :churn, 2) do
      apply(Trebejo.Git.Local, :churn, [path, opts])
    else
      {:error, :trebejo_not_loaded}
    end
  end

  defp persist_stats(stats, project) do
    Enum.each(stats, fn %{file: path, churn: churn, authors: authors} ->
      risk = churn * (1 + :math.log(max(length(authors), 1)))

      Repo.update_all(
        from(f in Schema.File,
          where:
            f.project_id == ^project.id and
              (f.path == ^path or f.path == ^Path.relative_to(path, project.path))
        ),
        set: [git_churn: churn, git_authors: authors, risk_score: risk]
      )
    end)
  end
end
