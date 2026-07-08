defmodule Delfos.Config.LLMDiscovery do
  @moduledoc """
  Detects whether the configured local LLM / embedding servers are running.

  Endpoint health is delegated to `Candil.Health`. Local llama.cpp startup is
  delegated to Candil engines instead of spawning `llama-server` directly.
  """

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
  Status of a single LLM endpoint. Includes model info for auto-start.
  """
  @type endpoint_status :: %{
          required(:role) => :embed | :llm,
          required(:url) => String.t(),
          required(:reachable) => boolean(),
          required(:provider) => atom() | String.t() | nil,
          required(:model) => String.t() | nil,
          optional(:api_key) => String.t() | nil,
          optional(:extra_args) => [String.t()],
          optional(:gguf_path) => String.t() | nil,
          optional(:llama_server_path) => String.t() | nil,
          optional(:download_precompiled) => boolean(),
          optional(:launcher) => String.t() | nil,
          optional(:suggested_start) => String.t()
        }

  @doc """
  If any endpoint is unreachable, prompts the user to start it. Returns
  `:all_running`, `:started_some`, or `:user_declined`.
  """
  @spec ensure_running(keyword() | endpoint_status()) ::
          :all_running | :started_some | :user_declined | :ok | {:error, term()}
  def ensure_running(opts \\ [])

  def ensure_running(%{url: url} = ep) do
    case health_module().probe(url, timeout: 2_000) do
      %{reachable: true} ->
        Alaja.print_info("#{ep.role} already running at #{url}, reusing")
        :ok

      _ ->
        Alaja.print_info("#{ep.role} not running, starting via Candil...")
        start_via_candil(ep)
    end
  end

  def ensure_running(opts) when is_list(opts) do
    auto_yes = Keyword.get(opts, :yes, false)

    statuses = status()
    down = Enum.filter(statuses, &(not &1.reachable))

    case down do
      [] ->
        :all_running

      endpoints ->
        if auto_yes do
          Enum.reduce_while(endpoints, :started_some, fn ep, acc ->
            if try_start(ep), do: {:cont, acc}, else: {:halt, acc}
          end)
        else
          offer_start_all(endpoints)
        end
    end
  end

  @doc false
  def start_via_candil(ep) do
    with :ok <- ensure_candil_started(),
         {:ok, engine} <- ensure_engine_registered(ep),
         {:ok, model} <- ensure_model_registered(ep),
         :ok <- start_candil_engine(engine, model) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
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
      extra_args: cfg[:extra_args] || [],
      gguf_path: cfg[:gguf_path],
      llama_server_path: cfg[:llama_server_path],
      download_precompiled: cfg[:download_precompiled],
      launcher: cfg[:launcher],
      reachable: Map.get(health, :reachable, false)
    }
  end

  # ── Auto-start ────────────────────────────────────────────────────────

  defp offer_start_all(endpoints) do
    Alaja.print_warning("Some local services are not running:")

    Enum.each(endpoints, fn ep ->
      Alaja.print_raw("  ✗ #{ep.role}: #{ep.url} (#{ep.model || "?"})\n")
    end)

    Alaja.print_raw("\n")

    case Alaja.Printer.Interactive.question_with_options(
           "Start them now?",
           [
             {"Yes, start all through Candil", :yes},
             {"No, I'll do it myself", :no}
           ]
         ) do
      :yes ->
        Enum.reduce_while(endpoints, :started_some, fn ep, acc ->
          if try_start(ep), do: {:cont, acc}, else: {:halt, acc}
        end)

      _ ->
        :user_declined
    end
  end

  defp try_start(%{reachable: true}), do: true

  defp try_start(ep) do
    case detect_provider(ep) do
      :ollama ->
        start_ollama(ep)

      :llama_cpp ->
        case ensure_running(ep) do
          :ok -> true
          {:error, reason} ->
            Alaja.print_warning("Could not start #{ep.role}: #{inspect(reason)}")
            false
        end

      :vllm ->
        start_vllm(ep)

      nil ->
        Alaja.print_warning("Don't know how to start #{ep.url}; skipping.")
        false
    end
  end

  defp detect_provider(%{provider: provider}) when provider in [:ollama, "ollama"], do: :ollama
  defp detect_provider(%{provider: provider}) when provider in [:local, "local", :llama_cpp, "llama_cpp"], do: :llama_cpp
  defp detect_provider(%{host: "127.0.0.1", port: 11434}), do: :ollama
  defp detect_provider(%{host: "localhost", port: 11434}), do: :ollama
  defp detect_provider(%{host: host, port: port}) when host in ["127.0.0.1", "localhost"] and port in [9998, 9999, 8080], do: :llama_cpp
  defp detect_provider(%{host: host, port: 8000}) when host in ["127.0.0.1", "localhost"], do: :vllm
  defp detect_provider(_), do: nil

  defp start_ollama(_ep) do
    case System.find_executable("ollama") do
      nil ->
        Alaja.print_error("ollama not found in PATH")
        false

      _path ->
        Alaja.print_info("Launching ollama serve in background...")
        _pid = spawn(fn -> System.cmd("ollama", ["serve"], stderr_to_stdout: true) end)
        Process.sleep(2_000)
        true
    end
  end

  defp start_vllm(_ep) do
    Alaja.print_info("vllm requires a Python environment — please run manually:")
    Alaja.print_raw("  source .venv/bin/activate && vllm serve <model> --port 8000\n")
    false
  end

  defp ensure_engine_registered(ep) do
    alias = engine_alias(ep.role)

    case registered_engine(alias) do
      nil ->
        engine = %Candil.Engine{
          alias: alias,
          binary_dir: binary_dir_from_path(Map.get(ep, :llama_server_path)),
          use_precompiled: Map.get(ep, :download_precompiled, true),
          host: ep.host,
          port: ep.port,
          start_args: ep.extra_args || [],
          launcher: resolve_launcher(Map.get(ep, :launcher))
        }

        candil_config_module().register_engine(engine)
        {:ok, engine}

      engine ->
        {:ok, engine}
    end
  end

  defp ensure_model_registered(ep) do
    alias = model_alias(ep.role)

    case registered_model(alias) do
      nil ->
        with {:ok, path} <- gguf_path(ep) do
          model = %Candil.Model{
            alias: alias,
            type: :local,
            model_dir: Path.dirname(path),
            filename: Path.basename(path),
            context_size: Map.get(ep, :context_size, 4096),
            engine: engine_alias(ep.role),
            usage: usage(ep.role)
          }

          candil_config_module().register_model(model)
          {:ok, model}
        end

      model ->
        {:ok, model}
    end
  end

  defp start_candil_engine(engine, model) do
    case candil_module().start_engine(engine, model) do
      {:ok, _pid} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp registered_engine(alias) do
    alias
    |> get_registered_engine()
    |> unwrap_registered()
  end

  defp registered_model(alias) do
    alias
    |> get_registered_model()
    |> unwrap_registered()
  end

  defp unwrap_registered({:ok, value}), do: value
  defp unwrap_registered({:error, :not_found}), do: nil
  defp unwrap_registered(nil), do: nil
  defp unwrap_registered(value), do: value

  defp get_registered_engine(alias), do: apply(candil_config_module(), :get_engine, [alias])
  defp get_registered_model(alias), do: apply(candil_config_module(), :get_model, [alias])

  defp candil_config_module,
    do: Application.get_env(:delfos, :candil_config, Candil.Config)

  defp gguf_path(%{gguf_path: path}) when is_binary(path) and path != "", do: {:ok, path}
  defp gguf_path(_ep), do: {:error, :missing_gguf_path}

  defp resolve_launcher(nil), do: nil
  defp resolve_launcher(""), do: nil
  defp resolve_launcher(module) when is_atom(module), do: module

  defp resolve_launcher(module_name) when is_binary(module_name) do
    module =
      module_name
      |> String.trim()
      |> String.replace_prefix("Elixir.", "")
      |> then(&String.to_atom("Elixir." <> &1))

    if Code.ensure_loaded?(module) and function_exported?(module, :launch, 2) do
      module
    else
      Alaja.print_warning(
        "Launcher #{module_name} not loaded or missing launch/2 — falling back to default"
      )

      nil
    end
  end

  defp binary_dir_from_path(nil), do: nil
  defp binary_dir_from_path(""), do: nil

  defp binary_dir_from_path(path) do
    if Path.basename(path) == "llama-server" do
      Path.dirname(path)
    else
      path
    end
  end

  defp ensure_candil_started do
    case Application.ensure_all_started(:candil) do
      {:ok, _apps} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp engine_alias(:embed), do: :embedding_engine
  defp engine_alias(:llm), do: :llm_engine
  defp model_alias(:embed), do: :embedding_model
  defp model_alias(:llm), do: :llm_model
  defp usage(:embed), do: [:embeddings]
  defp usage(:llm), do: [:chat, :completion]

  defp default_port_for(:embed), do: 9998
  defp default_port_for(:llm), do: 8080

  defp parse_url(url, role) do
    uri = URI.parse(url)

    %{
      host: uri.host || "127.0.0.1",
      port: uri.port || default_port_for_scheme(uri.scheme) || default_port_for(role)
    }
  end

  defp default_port_for_scheme("https"), do: 443
  defp default_port_for_scheme("http"), do: 80
  defp default_port_for_scheme(_scheme), do: nil

  defp health_module, do: Application.get_env(:delfos, :candil_health, Candil.Health)
  defp candil_module, do: Application.get_env(:delfos, :candil, Candil)
end
