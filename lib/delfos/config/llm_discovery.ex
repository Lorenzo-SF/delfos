defmodule Delfos.Config.LLMDiscovery do
  @moduledoc """
  Checks whether the configured LLM / embedding endpoints are reachable.

  Delfos does NOT manage LLM servers anymore: it only consumes endpoints
  (`ip:port` + `api_key` + `type`). If an endpoint is down, Delfos tells
  the user to start it themselves (e.g. with `runllama`).

  Endpoint health is delegated to `Candil.Health`.
  """

  require Logger

  alias Alaja
  alias Delfos.Config.Manager

  @doc """
  Returns the status of all configured LLM endpoints, with model info.
  """
  @spec status() :: [endpoint_status()]
  def status do
    [
      check_endpoint(:embed, Manager.embedding()),
      check_endpoint(:llm, Manager.llm())
    ]
  end

  @typedoc """
  Status of a single LLM endpoint.
  """
  @type endpoint_status :: %{
          required(:role) => :embed | :llm,
          required(:url) => String.t(),
          required(:reachable) => boolean(),
          required(:provider) => atom() | String.t() | nil,
          required(:model) => String.t() | nil,
          optional(:api_key) => String.t() | nil
        }

  @doc """
  Ensures the configured endpoints are reachable.

  Delfos never starts servers: if an endpoint is unreachable it prints a
  hint telling the user to start it themselves. Returns `:all_running`
  when everything is reachable, `:user_declined`/`:started_some` are kept
  for backward-compat with callers (they mean "not all running").
  """
  @spec ensure_running(keyword() | endpoint_status()) ::
          :all_running | :started_some | :user_declined | :ok | {:error, term()}
  def ensure_running(opts \\ [])

  def ensure_running(%{url: url} = ep) do
    case health_module().probe(url, timeout: 2_000, api_key: ep[:api_key]) do
      %{reachable: true} ->
        Alaja.print_info("#{ep.role} already running at #{url}, reusing")
        :ok

      _ ->
        print_down_hint(ep)
        {:error, :not_running}
    end
  end

  def ensure_running(opts) when is_list(opts) do
    statuses = status()
    down = Enum.filter(statuses, &(not &1.reachable))

    case down do
      [] ->
        :all_running

      endpoints ->
        if Keyword.get(opts, :yes, false) do
          Enum.each(endpoints, &print_down_hint/1)
          :started_some
        else
          offer_manual_start(endpoints)
        end
    end
  end

  # ── Private ───────────────────────────────────────────────────────────

  defp check_endpoint(role, cfg) do
    url = cfg[:url] || "http://127.0.0.1:#{default_port_for(role)}"
    %{host: host, port: port} = parse_url(url, role)
    health = health_module().probe(url, timeout: 2_000, api_key: cfg[:api_key])

    %{
      role: role,
      url: url,
      host: host,
      port: port,
      provider: cfg[:provider],
      model: cfg[:model],
      api_key: cfg[:api_key],
      reachable: Map.get(health, :reachable, false)
    }
  end

  defp offer_manual_start(endpoints) do
    Alaja.print_warning("Some configured endpoints are not running:")

    Enum.each(endpoints, fn ep ->
      print_down_hint(ep)
    end)

    Alaja.print_info(
      "Delfos does not start LLM servers. Start them yourself " <>
        "(e.g. `runllama start gpt-oss` / `runllama start embed`) and re-run."
    )

    :user_declined
  end

  defp print_down_hint(ep) do
    Alaja.print_warning(
      "✗ #{ep.role}: #{ep.url} (#{ep.model || "?"}) not reachable. " <>
        "Start it yourself (e.g. `runllama start <model>`) and re-run."
    )
  end

  defp default_port_for(:embed), do: 9998
  defp default_port_for(:llm), do: 9999

  defp parse_url(url, role) do
    uri = URI.parse(url)

    %{
      host: uri.host || "127.0.0.1",
      port: uri.port || default_port_for(role)
    }
  end

  defp health_module, do: Application.get_env(:delfos, :candil_health, Candil.Health)
end
