defmodule Delfos.Config.Probe do
  @moduledoc """
  Low-level probes for external services used by Delfos.

  Each probe returns `:ok` or `{:error, reason}`. Probes are stateless
  and can be called from diagnostics, CLI commands, or the health check
  GenServer.
  """

  alias Delfos.Repo

  @doc """
  Checks PostgreSQL connectivity with SELECT 1.
  """
  @spec check_db() :: :ok | {:error, String.t()}
  def check_db do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, %{message: msg}} -> {:error, msg}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e in [DBConnection.ConnectionError] -> {:error, Exception.message(e)}
  end

  @doc """
  Probes an LLM/embedding provider endpoint.

  Sends a minimal request to verify the service is running and
  responding. Uses `Apero.Llm.Health.ping/3` behind the scenes.
  """
  @spec check_provider(String.t(), String.t(), String.t() | nil, pos_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def check_provider(url, model, _api_key \\ nil, timeout \\ 5_000) do
    case Apero.Llm.Health.ping(url, model, timeout: timeout) do
      :ok ->
        %{status: :pass, label: "Provider #{model}", detail: "Responding at #{url}"}

      {:error, reason} ->
        %{status: :fail, label: "Provider #{model}", detail: reason, action: "Run: delfos setup llm"}
    end
  end

  @doc """
  Checks that the local filesystem has expected directories.
  """
  @spec check_data_dir() :: :ok | {:error, String.t()}
  def check_data_dir do
    data_dir = Application.app_dir(:delfos, "priv")
    models_dir = Delfos.Config.Manager.config_file() |> Path.dirname() |> Path.join("models")

    statuses = [
      {"app data dir", File.exists?(data_dir), data_dir},
      {"models dir", File.exists?(models_dir), models_dir}
    ]

    missing = Enum.filter(statuses, fn {_label, exists?, _path} -> not exists? end)

    case missing do
      [] -> :ok
      _ ->
        {:error,
         Enum.map_join(missing, "; ", fn {label, _exists?, path} -> "#{label}: #{path}" end)}
    end
  end
end
