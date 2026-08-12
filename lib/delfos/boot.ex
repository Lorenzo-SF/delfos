defmodule Delfos.Boot do
  @moduledoc """
  Startup-time checks for the Delfos application.

  SE-5 (S21): when Delfos starts in MCP mode, we run a quick preflight
  before advertising capabilities. If PostgreSQL or the embedding
  server is unreachable, we return empty capabilities so the MCP
  client knows we're degraded — better than letting the first
  tool call fail mysteriously.

  Currently uses Botica.Doctor 2.0's run/1 — no Botica 3.0 features
  required (just the parallel check execution, timeout per check,
  and aggregated status).

  For a more complete preflight (e.g. LLM provider reachability,
  embedding model loaded), see `Delfos.Config.Diagnostics.run/0`.
  """

  require Logger

  alias Delfos.Config.Diagnostics

  @critical_check_ids [
    # Postgres connectivity
    :postgres,
    # pgvector extension (required for vector storage)
    :pgvector,
    # Migrations applied (otherwise first INSERT crashes)
    :migrations,
    # Embedding provider reachable
    :embed_provider
  ]

  @doc """
  Runs the critical preflight checks. Returns:
    * `{:ok, summary}` — all critical checks passed.
    * `{:degraded, summary}` — non-critical checks failed, but
      core ones passed. MCP server can still serve some requests.
    * `{:failed, summary}` — at least one critical check failed.
      MCP server should advertise empty capabilities.

  Designed to NOT raise: failures are reported in the summary,
  not thrown. Always safe to call from `start/2` without
  crashing the supervisor.
  """
  @spec preflight() :: {:ok, map()} | {:degraded, map()} | {:failed, map()}
  def preflight do
    summary =
      try do
        %{}
        |> run_critical()
        |> count_results()
      catch
        kind, reason ->
          # If the whole thing blows up, treat it as failed with
          # a useful message — never crash the caller.
          %{
            ok: 0,
            failed: 1,
            error: "#{kind}: #{inspect(reason)}",
            results: []
          }
      end

    cond do
      summary.failed == 0 and summary.error == nil -> {:ok, summary}
      critical_failures(summary) == [] -> {:degraded, summary}
      true -> {:failed, summary}
    end
  end

  defp run_critical(acc) do
    # Run the full diagnostics suite and filter to critical checks.
    # This avoids calling Botica.Doctor twice (once for the preflight,
    # once for `delfos doctor`) — both use the same check defs.
    results =
      Diagnostics.run()
      |> Enum.filter(fn r -> Enum.member?(@critical_check_ids, r.id) end)

    Map.put(acc, :results, results)
  end

  defp count_results(%{results: results} = acc) do
    {ok, failed} =
      Enum.reduce(results, {0, 0}, fn r, {o, f} ->
        case Map.get(r, :status, :unknown) do
          :ok -> {o + 1, f}
          _ -> {o, f + 1}
        end
      end)

    Map.merge(acc, %{ok: ok, failed: failed})
  end

  defp critical_failures(%{results: results}) do
    Enum.filter(results, fn r ->
      not (r.status == :ok) and Enum.member?(@critical_check_ids, r.id)
    end)
  end
end
