defmodule Delfos.Health do
  @moduledoc """
  Periodic health check runner for Delfos.

  Runs Botica checks (PostgreSQL connectivity via Ecto, etc.) on a
  configurable interval and logs results. Activated via:

      config :delfos, :health_check, true

  Unlike `delfos doctor`, this module runs automatically in the
  background — it does not block or prompt for fixes.
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
    # Usamos Botica.Doctor.run/1 con un check inline para verificar
    # la conexión a PostgreSQL via Ecto. Esto integra Delfos.Health
    # con la infraestructura de checks de Botica (resultados tipados,
    # logging consistente, etc.) — ver M1.
    config = %{
      app_name: "delfos",
      checks: [db_check()]
    }

    case Botica.Doctor.run(config) do
      {:ok, results} ->
        Enum.each(results, fn r ->
          case r.status do
            :ok -> Logger.info("Health: #{r.name} ok")
            :error -> Logger.warning("Health: #{r.name} error: #{r.message}")
            :warning -> Logger.warning("Health: #{r.name} warning: #{r.message}")
          end
        end)

      {:error, reason} ->
        Logger.warning("Health: Botica runner error: #{inspect(reason)}")
    end
  rescue
    e -> Logger.warning("Health: check error: #{Exception.message(e)}")
  end

  defp db_check do
    %{
      id: :postgres_ecto,
      name: "PostgreSQL (Ecto)",
      description: "Database is reachable via SQL SELECT 1",
      priority: 1,
      tags: [:database, :critical],
      timeout: 5_000,
      check: fn ->
        case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
          {:ok, _} -> {:ok, "DB responded"}
          {:error, reason} -> {:error, "DB query failed: #{inspect(reason)}"}
        end
      end,
      fix: nil
    }
  end
end
