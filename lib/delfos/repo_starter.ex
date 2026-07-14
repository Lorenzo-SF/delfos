defmodule Delfos.RepoStarter do
  @moduledoc """
  Wraps `Delfos.Repo` so that the supervision tree always starts, even if
  PostgreSQL is unreachable. The Repo starts on first access and stays
  owned by this GenServer (not by transient task processes).
  """
  use GenServer
  require Logger

  require Logger

  alias Delfos.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # No intentamos conectar a DB en init/1 — eso bloquearía el supervisor
    # hasta que PostgreSQL responda (o haga timeout). La conexión se
    # establece bajo demanda en `start_repo/0`, que es llamado desde
    # los comandos CLI que realmente necesitan DB.
    {:ok, %{repo: nil}}
  end

  @doc """
  Ensures the Ecto repo is started. Returns `{:ok, pid}` or `{:error, reason}`.
  Safe to call multiple times — if the repo is already running it just verifies
  connectivity.
  """
  @spec start_repo() :: {:ok, pid()} | {:error, String.t()}
  def start_repo do
    case Process.whereis(Delfos.Repo) do
      nil -> GenServer.call(__MODULE__, :start_repo, 30_000)
      _pid -> verify_repo()
    end
  end

  @impl true
  def handle_call(:start_repo, _from, state) do
    result = do_start_repo()
    {:reply, result, state}
  end

  defp do_start_repo do
    prev_trap = Process.flag(:trap_exit, true)

    result =
      try do
        case Delfos.Repo.start_link() do
          {:ok, pid} ->
            verify_repo_with_check(pid)

          {:error, {:already_started, pid}} ->
            verify_repo_with_check(pid)

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      rescue
        e in [DBConnection.ConnectionError] ->
          {:error, "DB connection error: #{e.message}"}

        e in [Postgrex.Error] ->
          {:error, "Postgrex error: #{e.message || inspect(e)}"}

        error ->
          Logger.error("[RepoStarter] unexpected error: #{inspect(error)}")
          {:error, "unexpected: #{inspect(error)}"}
      catch
        :exit, reason -> {:error, "exit: #{inspect(reason)}"}
      after
        Process.flag(:trap_exit, prev_trap)
      end

    result
  end

  # Poll the DB with backoff until it responds or we hit the deadline.
  # Replaces the old blind `Process.sleep(300)` with proper polling.
  @db_poll_max_ms 10_000
  @db_poll_interval_ms 200

  defp verify_repo_with_check(pid) do
    deadline = System.monotonic_time(:millisecond) + @db_poll_max_ms
    poll_db(pid, deadline)
  end

  defp poll_db(pid, deadline) do
    case verify_repo() do
      {:ok, _} ->
        {:ok, pid}

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@db_poll_interval_ms)
          poll_db(pid, deadline)
        else
          {:error, "DB not reachable within #{@db_poll_max_ms}ms"}
        end
    end
  end

  defp verify_repo do
    try do
      case Repo.query("SELECT 1") do
        {:ok, _} -> {:ok, nil}
        {:error, reason} -> {:error, "query error: #{inspect(reason)}"}
      end
    rescue
      e in [DBConnection.ConnectionError] ->
        {:error, "DB not reachable: #{e.message}"}

      e in [Postgrex.Error] ->
        {:error, "Postgrex: #{e.message || inspect(e)}"}

      error ->
        Logger.error("[RepoStarter] verify_repo unexpected: #{inspect(error)}")
        {:error, "unexpected: #{inspect(error)}"}
    catch
      :exit, reason -> {:error, "connection lost: #{inspect(reason)}"}
    end
  end
end
