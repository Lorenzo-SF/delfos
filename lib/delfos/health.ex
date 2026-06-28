defmodule Delfos.Health do
  @moduledoc """
  Periodic health check runner for Delfos.

  Runs Botica checks (PostgreSQL connectivity, etc.) on a configurable
  interval and logs results. Activated via:

      config :delfos, :health_check, true
  """

  use GenServer
  require Logger

  alias Delfos.Repo

  @default_interval 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    interval = Application.get_env(:delfos, :health_interval, @default_interval)
    schedule_check(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:health_check, state) do
    run_checks()
    schedule_check(state.interval)
    {:noreply, state}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp run_checks do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} ->
        Logger.info("Health: DB ok")

      {:error, reason} ->
        Logger.warning("Health: DB error: #{inspect(reason)}")
    end
  rescue
    e -> Logger.warning("Health: DB error: #{Exception.message(e)}")
  end
end
