defmodule Delfos.Config.LLMDiscovery do
  @moduledoc """
  Detects whether the configured local LLM / embedding servers are running.

  Reads `~/.config/delfos/config.json` and probes the `embedding.url` and
  `llm.url` endpoints. If either is not responding, offers to start it
  locally (ollama, llama-server, vllm).

  Designed for the "it just works" UX: the user types `delfos init` and
  Delfos handles the rest.
  """

  alias Alaja
  alias Delfos.Config.Manager

  @doc """
  Returns the status of all configured LLM endpoints.
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
          required(:provider) => String.t() | nil,
          optional(:suggested_start) => String.t()
        }

  @doc """
  If any endpoint is unreachable, prompts the user to start it. Returns
  `:all_running`, `:started_some`, or `:user_declined`.
  """
  @spec ensure_running(keyword()) :: :all_running | :started_some | :user_declined
  def ensure_running(opts \\ []) do
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

  # ── Private ───────────────────────────────────────────────────────────

  defp check_endpoint(role, cfg) do
    url = cfg[:url] || "http://127.0.0.1:#{default_port_for(role)}"
    %{host: host, port: port} = parse_url(url)

    %{
      role: role,
      url: url,
      host: host,
      port: port,
      provider: cfg[:provider],
      reachable: port_open?(host, port, 1000)
    }
  end

  defp offer_start_all(endpoints) do
    Alaja.print_warning("Some local services are not running:")
    Enum.each(endpoints, fn ep -> Alaja.print_raw("  ✗ #{ep.role}: #{ep.url}\n") end)

    Alaja.print_raw("\n")

    case Alaja.Printer.Interactive.question_with_options(
           "Start them now?",
           [
             {"y. Yes, start all (ollama/llama-server)", :yes},
             {"n. No, I'll do it myself", :no}
           ]
         ) do
      :yes ->
        Enum.reduce_while(endpoints, :started_some, fn ep, acc ->
          if try_start(ep), do: {:cont, acc}, else: {:halt, acc}
        end)

      :no ->
        :user_declined
    end
  end

  defp try_start(%{reachable: true}), do: true

  defp try_start(ep) do
    provider = detect_provider(ep)

    case provider do
      nil ->
        Alaja.print_warning("Don't know how to start #{ep.url}; skipping.")
        false

      "ollama" ->
        start_ollama(ep)

      "llama-server" ->
        start_llama_server(ep)

      "vllm" ->
        start_vllm(ep)
    end
  end

  defp detect_provider(%{host: "127.0.0.1", port: 11434}), do: "ollama"
  defp detect_provider(%{host: "127.0.0.1", port: 9998}), do: "llama-server"
  defp detect_provider(%{host: "127.0.0.1", port: 8080}), do: "llama-server"
  defp detect_provider(%{host: "127.0.0.1", port: 8000}), do: "vllm"

  defp detect_provider(_), do: nil

  defp start_ollama(_ep) do
    case System.find_executable("ollama") do
      nil ->
        Alaja.print_error("ollama not found in PATH")
        false

      path ->
        Alaja.print_info("Launching ollama serve (detached)...")
        Port.open({:spawn_executable, path}, [:binary, :stream] ++ [{:args, ["serve"]}])
        Process.sleep(2_000)
        true
    end
  end

  defp start_llama_server(_ep) do
    case System.find_executable("llama-server") do
      nil ->
        Alaja.print_error("llama-server not found in PATH")
        false

      path ->
        Alaja.print_info("Launching llama-server (detached)...")
        Port.open({:spawn_executable, path}, [:binary, :stream] ++ [{:args, ["--help"]}])
        true
    end
  end

  defp start_vllm(_ep) do
    Alaja.print_info("vllm requires a Python environment — please run manually:")
    Alaja.print_raw("  source .venv/bin/activate && vllm serve <model> --port 8000\n")
    false
  end

  defp default_port_for(:embed), do: 9998
  defp default_port_for(:llm), do: 8080

  defp parse_url(url) do
    uri = URI.parse(url)
    %{host: uri.host || "127.0.0.1", port: uri.port || 5432}
  end

  defp port_open?(host, port, timeout_ms) do
    case :gen_tcp.connect(String.to_charlist(host), port, [], timeout_ms) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
