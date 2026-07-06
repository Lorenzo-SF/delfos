defmodule Delfos.RepoStarter do
  @moduledoc """
  Wraps `Delfos.Repo` so that the supervision tree always starts, even if
  PostgreSQL is unreachable. The Repo starts on first access and stays
  owned by this GenServer (not by transient task processes).
  """
  use GenServer

  alias Delfos.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Best-effort: attempt to start the repo immediately so that commands
    # like `delfos doctor` and `delfos init` can use Delfos.Repo without
    # crashing. If the DB is unreachable (no config, no server, etc.) the
    # error is logged and commands surface a friendly message later.
    try do
      do_start_repo()
    rescue
      e ->
        Logger.debug("[RepoStarter] deferred: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    catch
      :exit, reason ->
        Logger.debug("[RepoStarter] deferred (exit): #{inspect(reason)}")
        {:error, "exit: #{inspect(reason)}"}
    end

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
      nil -> GenServer.call(__MODULE__, :start_repo, :infinity)
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
            Process.sleep(300)
            verify_repo_with_check(pid)

          {:error, {:already_started, pid}} ->
            verify_repo_with_check(pid)

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      rescue
        error -> {:error, "rescue: #{inspect(error)}"}
      catch
        :exit, reason -> {:error, "exit: #{inspect(reason)}"}
      after
        Process.flag(:trap_exit, prev_trap)
      end

    result
  end

  defp verify_repo_with_check(pid) do
    case verify_repo() do
      {:ok, _} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_repo do
    try do
      case Repo.query("SELECT 1") do
        {:ok, _} -> {:ok, nil}
        {:error, reason} -> {:error, inspect(reason)}
      end
    rescue
      error -> {:error, "repo not started: #{inspect(error)}"}
    catch
      :exit, reason -> {:error, "connection lost: #{inspect(reason)}"}
    end
  end
end
