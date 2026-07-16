defmodule Delfos.Config.Probe do
  @moduledoc """
  Low-level probes for external services used by Delfos.

  Each probe returns `:ok` or `{:error, reason}`. Probes are stateless
  and can be called from diagnostics, CLI commands, or the health check
  GenServer.
  """

  alias Delfos.Repo
  alias Delfos.RepoStarter

  @doc """
  Checks PostgreSQL connectivity with SELECT 1.
  Ensures the repo is started first via `RepoStarter.start_repo/0`.
  """
  @spec check_db() :: :ok | {:error, String.t()}
  def check_db do
    with {:ok, _pid} <- RepoStarter.start_repo(),
         {:ok, _result} <- query_repo() do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp query_repo do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> {:ok, nil}
      {:error, %{message: msg}} -> {:error, msg}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e in [DBConnection.ConnectionError] -> {:error, Exception.message(e)}
  end

  @doc """
  Probes an LLM/embedding provider endpoint.

  Sends a minimal request to verify the service is running and
  responding. Uses `Candil.Health.ping/3` behind the scenes.

  The hint returned on failure is tailored to the endpoint: a local
  URL gets "start llama-server" advice, a remote URL gets "check
  credentials" advice.
  """
  @spec check_provider(String.t(), String.t(), String.t() | nil, pos_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def check_provider(url, model, api_key \\ nil, timeout \\ 5_000) do
    # Bug #13 fix: antes el parámetro api_key se ignoraba
    # (underscore-prefixed), por lo que el probe fallaba con
    # HTTP 401 en servidores que requieren auth (como llama-server
    # con --api-key). Ahora enviamos 'Authorization: Bearer' si
    # tenemos key. Si no hay key, el probe sigue funcionando
    # contra servidores sin auth.
    headers = build_auth_headers(api_key)

    case ping_with_auth(url, model, timeout, headers) do
      :ok ->
        %{status: :pass, label: "Provider #{model}", detail: "Responding at #{url}"}

      {:error, reason} ->
        # Bug #9 fix: formatear el reason en vez de volcar la struct.
        # Antes salía "%Req.TransportError{reason: :econnrefused}"
        # en pantalla; ahora muestra algo como "unreachable at
        # http://...:9998 (econnrefused)".
        formatted = format_probe_error(reason, url)

        %{
          status: :fail,
          label: "Provider #{model}",
          detail: formatted,
          action: action_for(url)
        }
    end
  end

  # Construye headers de Authorization si hay api_key. Si no, []
  # (compatible con servidores sin auth).
  defp build_auth_headers(nil), do: []
  defp build_auth_headers(""), do: []
  defp build_auth_headers(key) when is_binary(key), do: [{"authorization", "Bearer #{key}"}]

  # Wrapper sobre Candil.Health.ping/3 que añade headers de auth.
  # Candil no acepta headers directamente, así que usamos Candil.HTTP.get/3
  # que tiene circuit breaker, retry y rate limiting integrados.
  #
  # Usamos /v1/models (GET) en vez de /v1/embeddings (POST) porque
  # el endpoint de embeddings no está implementado en servidores de
  # chat (HTTP 501). /v1/models es estándar OpenAI y ambos tipos
  # de servidores lo implementan.
  defp ping_with_auth(url, _model, timeout, headers) do
    url = String.trim_trailing(url, "/")

    case Candil.HTTP.get("#{url}/v1/models", headers, timeout_ms: timeout) do
      {:ok, _resp} ->
        :ok

      {:error, %Candil.Error{reason: reason, context: ctx}} ->
        msg = Map.get(ctx, :message, inspect(ctx))
        {:error, "#{reason}: #{msg}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # Convierte errores crudos (structs, atoms, strings) en mensajes
  # user-facing. Maneja los casos comunes del probe.
  defp format_probe_error(reason, _url) when is_binary(reason), do: reason
  defp format_probe_error(reason, url) when is_atom(reason), do: "#{reason} at #{url}"
  defp format_probe_error(reason, _url), do: inspect(reason)

  # Pick a recovery hint based on the URL. Local providers should be
  # started; remote ones need a credential check.
  defp action_for("http://127.0.0.1:" <> _),
    do: "Start it locally: llama-server (or run scripts/register-local-llms.sh --probe to verify)"

  defp action_for("http://localhost:" <> _),
    do: "Start it locally: llama-server (or run scripts/register-local-llms.sh --probe to verify)"

  defp action_for(_),
    do: "Run: delfos config setup llm  (check URL, API key, and network)"

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
      [] ->
        :ok

      _ ->
        {:error,
         Enum.map_join(missing, "; ", fn {label, _exists?, path} -> "#{label}: #{path}" end)}
    end
  end
end
