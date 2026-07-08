defmodule Delfos.Config.LLMDiscovery do
  @moduledoc """
  Detects whether the configured local LLM / embedding servers are running.

  Reads `~/.config/delfos/config.json` and probes the `embedding.url` and
  `llm.url` endpoints. If either is not responding, offers to start it
  locally (ollama, llama-server, vllm).

  Designed for the "it just works" UX: the user types `delfos init` and
  Delfos handles the rest.

  ## Health probe levels

  1. **TCP port check** — quick check if the port is open (milliseconds).
  2. **HTTP health check** — sends `GET /health` with timeout, checks
     response. Catches processes that are listening but not serving
     (e.g. stalled model load, dead but port still open).
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
          required(:provider) => String.t() | nil,
          required(:model) => String.t() | nil,
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

    # Nivel 1: TCP port check rápido
    tcp_open = port_open?(host, port, 1000)

    # Nivel 2: HTTP health check — verifica que el proceso responde
    # en HTTP (no solo que el puerto está abierto). Esto detecta
    # procesos que escuchan pero no sirven (modelo atascado, etc.)
    health_ok = if tcp_open, do: http_health_check?(host, port), else: false

    %{
      role: role,
      url: url,
      host: host,
      port: port,
      provider: cfg[:provider],
      model: cfg[:model],
      reachable: health_ok
    }
  end

  # ── HTTP health check (raw TCP, sin dependencias HTTP) ────────────────

  defp http_health_check?(host, port) do
    case :gen_tcp.connect(
           String.to_charlist(host),
           port,
           [],
           3000
         ) do
      {:ok, socket} ->
        result =
          case send_http_get(socket, "/health", host) do
            {:ok, body} ->
              # Health endpoint returns {"status":"ok"} for llama-server
              String.contains?(body, "ok") or String.contains?(body, "OK")

            _ ->
              false
          end

        :gen_tcp.close(socket)
        result

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp send_http_get(socket, path, host) do
    request = "GET #{path} HTTP/1.0\r\nHost: #{host}\r\nConnection: close\r\n\r\n"
    :gen_tcp.send(socket, request)

    case :gen_tcp.recv(socket, 0, 3000) do
      {:ok, data} -> {:ok, List.to_string(data)}
      error -> error
    end
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
             {"Yes, start all (llama-server)", :yes},
             {"No, I'll do it myself", :no}
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
  defp detect_provider(%{host: "127.0.0.1", port: 9999}), do: "llama-server"
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

  defp start_llama_server(ep) do
    # Try ~/bin/llama-run first (the user's preferred wrapper)
    llama_run = Path.expand("~/bin/llama-run")

    if File.exists?(llama_run) do
      start_via_llama_run(llama_run, ep)
    else
      start_via_llama_server_raw(ep)
    end
  end

  defp start_via_llama_run(llama_run, ep) do
    model_arg = if ep.role == :embed, do: "embed", else: "gpt-oss"
    Alaja.print_info("Starting #{ep.role} via llama-run (#{model_arg})...")

    # Kill any existing llama-server on this port first
    _ =
      System.cmd("pkill", ["-9", "-f", "llama-server.*--port #{ep.port}"],
        stderr: :ignore
      )

    Process.sleep(1000)

    # Start llama-run in background via Port (non-blocking)
    _port =
      Port.open(
        {:spawn_executable, llama_run},
        [:binary, :stream, :exit_status, {:args, [model_arg]}]
      )

    # Give it a moment to start
    Process.sleep(2000)

    # Verify it's up
    if port_open?(ep.host, ep.port, 5000) do
      Alaja.print_info("#{ep.role} started on #{ep.host}:#{ep.port}")
      true
    else
      Alaja.print_warning(
        "#{ep.role} may not be ready yet — check logs: /tmp/delfos_llm_logs/"
      )
      true
    end
  end

  defp start_via_llama_server_raw(ep) do
    case System.find_executable("llama-server") do
      nil ->
        Alaja.print_error(
          "llama-server not found in PATH. Install it or create ~/bin/llama-run"
        )

        Alaja.print_info("See: https://github.com/ggml-org/llama.cpp")
        false

      path ->
        Alaja.print_info("Starting llama-server for #{ep.role} (raw)...")

        Port.open(
          {:spawn_executable, path},
          [
            :binary,
            :stream,
            :exit_status,
            {:args,
             [
               "--port", "#{ep.port}",
               "--host", "127.0.0.1",
               "--api-key", "sk-local-dev-key",
               "--alias", "#{ep.model || ep.role}",
               "--no-mmap",
               "--jinja",
               "--flash-attn", "on",
               "--parallel", "1"
             ]}
          ]
        )

        Process.sleep(2_000)

        if port_open?(ep.host, ep.port, 3000) do
          Alaja.print_info("llama-server started on #{ep.host}:#{ep.port}")
          true
        else
          Alaja.print_warning("llama-server launched but not yet listening")
          true
        end
    end
  end

  defp start_vllm(_ep) do
    Alaja.print_info("vllm requires a Python environment — please run manually:")
    Alaja.print_raw("  source .venv/bin/activate && vllm serve <model> --port 8000\n")
    false
  end

  defp default_port_for(:embed), do: 9998
  defp default_port_for(:llm), do: 9999

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
