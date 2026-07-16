defmodule Delfos.Config.LLMDiscovery do
  @moduledoc """
  Detects whether the configured local LLM / embedding servers are running,
  and starts them on demand.

  Endpoint health is delegated to `Candil.Health`. Local llama.cpp startup
  is delegated to Candil engines (heavy path) or to the `llama-run` wrapper
  via `Arrea.LongRunning` (lightweight path) — see
  `ensure_embedding_server/1` and `ensure_running/1`.

  ## Key entry points (added in v2.4.0)

    * `ensure_embedding_server/1` — auto-arranque del embed server desde
      `delfos init` y `delfos doctor --fix`. User request:
      "que sea delfos el que lo arranque si no está".
    * `ensure_running/1` — prompts (or auto-starts, with `yes: true`) all
      down local endpoints through the Candil engine.
    * `recommended_embed_ngl/0` — VRAM-aware choice between GPU offload
      (n_gpu_layers=99) and CPU (0) for the local embed server.

  ## Pre-v2.4.0 behavior

  Before v2.4.0 this module only checked status and offered manual start;
  the embed server had to be running before `delfos init` was called,
  otherwise the scan would log "embedding unavailable" for every chunk.
  """

  require Logger

  alias Alaja
  alias Apero.Proc
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

  @doc """
  Ensures the embedding server is running. If not, attempts to start it automatically.

  Returns:
    - `:already_running` if the URL is already reachable
    - `:started` if successfully started via llama-run or Candil
    - `:not_applicable` if the provider is not local (cloud embeddings)
    - `{:error, reason}` if failed to start

  ## Options
    * `:yes` — skip user prompts (for non-interactive mode)
  """
  @spec ensure_embedding_server(keyword()) ::
          :already_running | :started | :not_applicable | {:error, term()}
  def ensure_embedding_server(opts \\ []) do
    cfg = Manager.embedding()

    # Check if provider is local
    case detect_provider(%{provider: cfg[:provider]}) do
      :llama_cpp ->
        # Local provider, check if reachable
        url = cfg[:url] || "http://127.0.0.1:9998"

        case health_module().probe(url, timeout: 2_000) do
          %{reachable: true} ->
            :already_running

          _ ->
            # Not reachable, attempt to start
            start_local_embed_server(cfg, opts)
        end

      _ ->
        # Non-local provider (cloud), no need to start local server
        :not_applicable
    end
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
          :ok ->
            true

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

  defp detect_provider(%{provider: provider})
       when provider in [:local, "local", :llama_cpp, "llama_cpp"], do: :llama_cpp

  defp detect_provider(%{host: "127.0.0.1", port: 11434}), do: :ollama
  defp detect_provider(%{host: "localhost", port: 11434}), do: :ollama

  defp detect_provider(%{host: host, port: port})
       when host in ["127.0.0.1", "localhost"] and port in [9998, 9999, 8080], do: :llama_cpp

  defp detect_provider(%{host: host, port: 8000}) when host in ["127.0.0.1", "localhost"],
    do: :vllm

  defp detect_provider(_), do: nil

  defp start_ollama(_ep) do
    case Proc.which("ollama") do
      nil ->
        Alaja.print_error("ollama not found in PATH")
        false

      _path ->
        Alaja.print_info("Launching ollama serve via Arrea.LongRunning...")
        Application.ensure_all_started(:arrea)

        case Arrea.LongRunning.start_link(
               id: :ollama_serve,
               binary: "ollama",
               args: ["serve"],
               health: fn ->
                 case Candil.Health.probe("http://127.0.0.1:11434", timeout: 1_000) do
                   %{reachable: true} -> :ok
                   _ -> {:error, :not_ready}
                 end
               end
             ) do
          {:ok, _pid} ->
            # Esperar hasta que ollama responda (max 10s)
            wait_for_ollama(10_000)
            true

          {:error, reason} ->
            Alaja.print_error("Could not start ollama: #{inspect(reason)}")
            false
        end
    end
  end

  defp wait_for_ollama(deadline_ms) when deadline_ms <= 0, do: :ok

  defp wait_for_ollama(deadline_ms) do
    case Candil.Health.probe("http://127.0.0.1:11434", timeout: 1_000) do
      %{reachable: true} ->
        :ok

      _ ->
        Process.sleep(500)
        wait_for_ollama(deadline_ms - 500)
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

  defp get_registered_engine(alias), do: candil_config_module().get_engine(alias)
  defp get_registered_model(alias), do: candil_config_module().get_model(alias)

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
  defp default_port_for_scheme(_), do: nil

  @doc """
  Decides the recommended `n_gpu_layers` for the local embed server.

  Rules (apply in order):
    1. If `LLAMA_EMBED_NGL` env var is set explicitly (a number), use it.
       This is the manual override path.
    2. If `LLAMA_EMBED_NGL_AUTO=auto` (or unset and configured as auto in
       `config/config.exs`), compute a recommendation based on chat
       provider and **available VRAM**:
         * Embed provider is cloud (openai / anthropic / anything not
           `:local`) — embed isn't local, NGL is irrelevant. Returns
           `:not_applicable`.
         * Embed provider is `:local`, chat is cloud — no VRAM
           contention. Returns `99` (full GPU offload for speed).
         * Embed provider is `:local`, chat is `:local`, chat looks
           heavy (`gpt-oss` 20B class) — returns `0` (CPU embed) to
           avoid OOM on a single GPU. Heavy is heuristically any
           model name matching `/20B|30B|40B|70B|gpt-oss|llama-3\\.\\d+-?\\d{2}B/i`.
         * Embed provider is `:local`, chat is `:local`, chat is
           small (everything else) — measure free VRAM via
           `nvidia-smi`. If free VRAM (MB) ≥ model GGUF size (MB) +
           1500 MB headroom for KV cache + activations, return
           `99`; otherwise return `0`. If `nvidia-smi` is missing
           (CPU-only box), return `0`.

  Returns either an `integer()` (the recommended NGL) or
  `:not_applicable` when the embed server isn't local.
  """
  @spec recommended_embed_ngl() :: integer() | :not_applicable
  def recommended_embed_ngl do
    case System.get_env("LLAMA_EMBED_NGL") do
      nil ->
        auto_recommend()

      str ->
        case Integer.parse(str) do
          {n, _} -> n
          :error -> auto_recommend()
        end
    end
  end

  defp auto_recommend do
    embed_cfg = Manager.embedding()
    llm_cfg = Manager.llm()

    # `Manager.embedding/llm` normalises the `provider` key as an atom
    # via `String.to_existing_atom/1`, which returns the default `:local`
    # when the runtime-provided string doesn't match a pre-loaded atom.
    # So we compare against both atom and string shapes to be safe.
    embed_local? = embed_local?(embed_cfg[:provider])
    llm_local? = llm_local?(llm_cfg[:provider])

    cond do
      not embed_local? ->
        :not_applicable

      not llm_local? ->
        # Chat is cloud, embed can have the GPU.
        99

      heavy_chat?(to_string(llm_cfg[:model] || "")) ->
        # Chat is local AND heavy → don't compete for the same VRAM.
        0

      true ->
        # Chat is local but small. Check actual VRAM before deciding
        # 99 vs 0 — that's the rule that prevents OOM.
        decide_by_vram()
    end
  end

  # Returns 99 if free VRAM comfortably fits the GGUF + 1.5 GB headroom
  # for KV cache + activations. Returns 0 otherwise (CPU only).
  # If we can't estimate (no nvidia-smi, no GGUF on disk), defaults
  # to 99 — the user will see OOM if it really doesn't fit, but
  # better to try than to silently run CPU.
  @vram_headroom_mb 1500

  defp decide_by_vram do
    case {estimate_model_vram_mb(), available_vram_mb()} do
      {nil, _} ->
        # Can't estimate model size — trust the user wanted GPU.
        99

      {_, nil} ->
        # No GPU at all (or nvidia-smi missing). Run on CPU.
        0

      {required, available} when required + @vram_headroom_mb < available ->
        # Plenty of room. Full GPU offload.
        99

      {required, available} ->
        Logger.info(
          "[LlmDiscovery] VRAM insuficiente para embed en GPU: " <>
            "modelo necesita ~#{required} MB + #{@vram_headroom_mb} MB headroom, " <>
            "pero solo hay #{available} MB libres. " <>
            "Cambiando a NGL=0 (CPU)."
        )

        0
    end
  end

  @doc """
  Estimates the embed model's VRAM footprint by reading its GGUF
  file size. Returns the size in MB, or `nil` if the file isn't
  found / readable.

  The GGUF size is a good proxy for VRAM: a Q8_0 quantised model
  lives entirely in VRAM (no CPU spill) when offloaded.
  """
  @spec estimate_model_vram_mb() :: pos_integer() | nil
  def estimate_model_vram_mb do
    case gguf_path() do
      nil ->
        nil

      path ->
        case File.stat(path) do
          {:ok, %{size: bytes}} ->
            ceil(bytes / (1024 * 1024))

          _ ->
            nil
        end
    end
  end

  # Locate the GGUF on disk. Priority:
  #
  #  1. Compile-time `:delfos, :embedding, :model` filename resolved
  #     against `GGUF_DIR` (or `$HOME/models/gguf`). This is the
  #     AUTHORITATIVE source — `~/bin/llama-run` reads the SAME env var,
  #     so the VRAM estimate will always match what actually loads.
  #  2. Fall back to the runtime JSON's `embedding.gguf_path` only if
  #     no compile-time file is present (e.g. a user-set path to a
  #     non-default model).
  #
  # The previous version put JSON first, which was a stale-data trap:
  # the JSON often kept pointing at an old model even after
  # `config/config.exs` was updated.
  defp gguf_path do
    gguf_dir =
      System.get_env(
        "GGUF_DIR",
        Path.join([System.get_env("HOME", "/root"), "models", "gguf"])
      )

    compile_time_path =
      case Application.fetch_env!(:delfos, :embedding)[:model] do
        model when is_binary(model) ->
          candidate = Path.join(gguf_dir, model)

          if File.exists?(candidate),
            do: candidate,
            else: nil

        _ ->
          nil
      end

    case compile_time_path do
      nil ->
        # No compile-time model on disk; fall back to whatever JSON says
        # (which is `embedding.gguf_path` if set).
        embed_cfg = Manager.embedding()

        if is_binary(embed_cfg[:gguf_path]) and File.exists?(embed_cfg[:gguf_path]),
          do: embed_cfg[:gguf_path],
          else: nil

      path ->
        path
    end
  end

  @doc """
  Returns the maximum free VRAM across all NVIDIA GPUs in MB, or
  `nil` if no GPU / no `nvidia-smi`.

  Parses the output of:

      nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits

  which prints one integer per GPU in MiB.
  """
  @spec available_vram_mb() :: pos_integer() | nil
  def available_vram_mb do
    case Proc.which("nvidia-smi") do
      nil ->
        nil

      _ ->
        case System.cmd("nvidia-smi", ["--query-gpu=memory.free", "--format=csv,noheader,nounits"]) do
          {output, 0} ->
            output
            |> String.split("\n", trim: true)
            |> Enum.map(&String.trim/1)
            |> Enum.map(&Integer.parse/1)
            |> Enum.flat_map(fn
              {n, _} -> [n]
              :error -> []
            end)
            |> Enum.filter(&(&1 > 0))
            |> case do
              [] -> nil
              values -> Enum.max(values)
            end

          _ ->
            nil
        end
    end
  end

  defp embed_local?(p) when p in [nil, :local, "local"], do: true
  defp embed_local?(_), do: false

  defp llm_local?(p) when p in [nil, :local, "local"], do: true
  defp llm_local?(_), do: false

  # Heuristic for "this chat model would crowd the GPU if the embed
  # model is also on it." Matches 7B+ class models that take ≥10 GB.
  defp heavy_chat?(model) when is_binary(model) do
    Regex.match?(~r/(20B|30B|40B|70B|gpt-oss|llama-3\.\d+-?\d{2}B|mixtral)/i, model)
  end

  defp heavy_chat?(_), do: true

  defp start_local_embed_server(cfg, _opts) do
    # Try llama-run first (lightweight)
    case Proc.which("llama-run") do
      nil ->
        # Fallback to Candil engine approach
        start_via_candil(cfg)

      path ->
        # Start via llama-run
        Application.ensure_all_started(:arrea)

        # Stop any existing embed server first
        Arrea.LongRunning.stop(:delfos_embed_server)

        # Start new embed server
        case Arrea.LongRunning.start_link(
               id: :delfos_embed_server,
               binary: path,
               args: ["embed"],
               health: fn ->
                 case health_module().probe(cfg[:url] || "http://127.0.0.1:9998", timeout: 1_000) do
                   %{reachable: true} -> :ok
                   _ -> {:error, :not_ready}
                 end
               end
             ) do
          {:ok, _pid} ->
            # Wait for server to be ready (max 10 seconds)
            wait_for_embed_server(10_000)
            :started

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp wait_for_embed_server(deadline_ms) when deadline_ms <= 0, do: :ok

  defp wait_for_embed_server(deadline_ms) do
    case health_module().probe("http://127.0.0.1:9998", timeout: 1_000) do
      %{reachable: true} ->
        :ok

      _ ->
        Process.sleep(500)
        wait_for_embed_server(deadline_ms - 500)
    end
  end

  defp health_module, do: Application.get_env(:delfos, :candil_health, Candil.Health)
  defp candil_module, do: Application.get_env(:delfos, :candil, Candil)
end
