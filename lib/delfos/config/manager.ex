defmodule Delfos.Config.Manager do
  @moduledoc """
  Gestiona la configuración global de Delfos en ~/.config/delfos/config.json

  Las API keys se almacenan cifradas con AES-256-GCM (vía Erlang `:crypto`)
  y se descifran automáticamente al leer. La clave de cifrado se genera
  aleatoriamente con `:crypto.strong_rand_bytes/1` y se guarda en
  ~/.config/delfos/.key.

  Variables de entorno tienen precedencia sobre el fichero de config.
  """

  require Logger

  @default_config_dir Path.expand("~/.config/delfos")

  # Runtime-resolved paths — swap via `Application.put_env(:delfos, :config_dir, ...)`
  # in tests so we never touch the real ~/.config/delfos.
  defp cfg_dir, do: Application.get_env(:delfos, :config_dir, @default_config_dir)
  defp cfg_file_path, do: Path.join(cfg_dir(), "config.json")
  defp key_file_path, do: Path.join(cfg_dir(), ".key")
  defp legacy_toml_path, do: Path.join(cfg_dir(), "delfos.conf")

  @default_config %{
    "embedding" => %{
      "provider" => "local",
      "url" => "http://127.0.0.1:9998",
      "model" => "bge-m3",
      "api_key" => "sk-local-dev-key",
      "dim" => 4096,
      "batch_size" => 48,
      "timeout_ms" => 25_000,
      "extra_args" => [],
      "gguf_path" => nil,
      "llama_server_path" => nil,
      "download_precompiled" => true,
      "launcher" => nil
    },
    "llm" => %{
      "provider" => "local",
      "url" => "http://127.0.0.1:9999",
      "model" => "gpt-oss",
      "api_key" => "sk-local-dev-key",
      "timeout_ms" => 45_000,
      "explain_max_tokens" => 600,
      "query_max_tokens" => 512,
      "thinker_url" => nil,
      "thinker_model" => nil,
      "use_thinker_for_query" => false,
      "extra_args" => [],
      "gguf_path" => nil,
      "llama_server_path" => nil,
      "download_precompiled" => true,
      "launcher" => nil
    },
    "retrieval" => %{
      "vector_weight" => 0.55,
      "bm25_weight" => 0.25,
      "graph_weight" => 0.20,
      "top_k" => 25,
      "final_k" => 7
    },
    "analysis" => %{
      "churn_max_commits" => 1000
    },
    "indexing" => %{
      "max_chunk_tokens" => 512,
      "ignore_dirs" => [
        "_build",
        "deps",
        "node_modules",
        "target",
        ".git",
        "dist",
        "coverage",
        "__pycache__",
        ".elixir_ls",
        "vendor",
        "Pods",
        ".gradle",
        ".venv",
        "build",
        ".dart_tool",
        "tmp",
        "graphify-out",
        "priv/static",
        ".terraform"
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Lectura
  # ---------------------------------------------------------------------------

  @doc "Carga la configuración desde ~/.config/delfos/config.json"
  @spec load() :: map()
  def load do
    ensure_config_exists()

    case File.read(cfg_file_path()) do
      {:ok, content} when content != "" ->
        case Jason.decode(content) do
          {:ok, parsed} -> apply_env_overrides(decrypt_values(parsed))
          {:error, _} -> @default_config
        end

      _ ->
        @default_config
    end
  end

  @doc "Alias for load/0 used by setup code."
  @spec read() :: map()
  def read, do: load()

  # Compile-time固定 values for `[embedding]`. Captured at module
  # compile time (Application.compile_env/3 cannot be called from
  # inside functions) and applied as overrides on every read of
  # the JSON config. The JSON may still hold `"model":
  # "mxbai-embed-v1"` from a pre-refactor session — we ignore
  # that for the read path the same way `delfos config set` ignores
  # it on the write path.
  @compile_embed_model     Application.compile_env(:delfos, :embedding, [])[:model]
  @compile_embed_dim       Application.compile_env(:delfos, :embedding, [])[:dim]
  @compile_embed_pooling   Application.compile_env(:delfos, :embedding, [])[:pooling] || "last"
  @compile_embed_ngl       Application.compile_env(:delfos, :embedding, [])[:n_gpu_layers] || 99

  @doc "Returns the `[embedding]` section of the configuration."
  @spec embedding() :: keyword()
  def embedding do
    cfg = load()

    [
      provider: get_atom(cfg, ["embedding", "provider"], :local),
      url: get_str(cfg, ["embedding", "url"], "http://127.0.0.1:9998"),
      model: @compile_embed_model || get_str(cfg, ["embedding", "model"], "bge-m3"),
      api_key: get_str(cfg, ["embedding", "api_key"], "sk-local-dev-key"),
      dim: @compile_embed_dim || get_int(cfg, ["embedding", "dim"], 4096),
      pooling: @compile_embed_pooling,
      ctx_size: get_int(cfg, ["embedding", "ctx_size"], 32_768),
      n_gpu_layers:
        case get_int(cfg, ["embedding", "n_gpu_layers"], nil) do
          nil -> @compile_embed_ngl
          n -> n
        end,
      slot_dir:
        get_str(
          cfg,
          ["embedding", "slot_dir"],
          "/tmp/delfos-embeddings-cache"
        ),
      batch_size: get_int(cfg, ["embedding", "batch_size"], 512),
      ubatch_size: get_int(cfg, ["embedding", "ubatch_size"], 512),
      timeout_ms: get_int(cfg, ["embedding", "timeout_ms"], 25_000),
      extra_args: get_list(cfg, ["embedding", "extra_args"], []),
      gguf_path: get_str(cfg, ["embedding", "gguf_path"], nil),
      llama_server_path: get_str(cfg, ["embedding", "llama_server_path"], nil),
      download_precompiled: get_bool(cfg, ["embedding", "download_precompiled"], true),
      launcher: get_str(cfg, ["embedding", "launcher"], nil)
    ]
  end

  @doc "Returns the `[llm]` section of the configuration."
  @spec llm() :: keyword()
  def llm do
    cfg = load()

    [
      provider: get_atom(cfg, ["llm", "provider"], :local),
      url: get_str(cfg, ["llm", "url"], "http://127.0.0.1:9999"),
      model: get_str(cfg, ["llm", "model"], "gpt-oss"),
      api_key: get_str(cfg, ["llm", "api_key"], "sk-local-dev-key"),
      timeout_ms: get_int(cfg, ["llm", "timeout_ms"], 45_000),
      # Deprecated: use [summarize] section instead. Kept for backward compat.
      summarize_max_tokens: get_int(cfg, ["llm", "summarize_max_tokens"], 180),
      explain_max_tokens: get_int(cfg, ["llm", "explain_max_tokens"], 600),
      query_max_tokens: get_int(cfg, ["llm", "query_max_tokens"], 512),
      thinker_url: get_str(cfg, ["llm", "thinker_url"], nil),
      thinker_model: get_str(cfg, ["llm", "thinker_model"], nil),
      use_thinker_for_query: get_bool(cfg, ["llm", "use_thinker_for_query"], false),
      extra_args: get_list(cfg, ["llm", "extra_args"], []),
      gguf_path: get_str(cfg, ["llm", "gguf_path"], nil),
      llama_server_path: get_str(cfg, ["llm", "llama_server_path"], nil),
      download_precompiled: get_bool(cfg, ["llm", "download_precompiled"], true),
      launcher: get_str(cfg, ["llm", "launcher"], nil)
    ]
  end

  @doc """
  Returns the `[summarize]` section of the configuration.

  Returns `nil` when the section is not present — the caller should
  fall back to `llm/0` for summarisation tasks.
  """
  @spec summarize() :: keyword() | nil
  def summarize do
    cfg = load()
    raw = Map.get(cfg, "summarize")

    if raw && map_size(raw) > 0 do
      [
        provider: get_atom(cfg, ["summarize", "provider"], :local),
        url: get_str(cfg, ["summarize", "url"], "http://127.0.0.1:9999"),
        model: get_str(cfg, ["summarize", "model"], "gpt-oss"),
        api_key: get_str(cfg, ["summarize", "api_key"], "sk-local-dev-key"),
        timeout_ms: get_int(cfg, ["summarize", "timeout_ms"], 45_000),
        max_tokens: get_int(cfg, ["summarize", "max_tokens"], 180),
        extra_args: get_list(cfg, ["summarize", "extra_args"], []),
        gguf_path: get_str(cfg, ["summarize", "gguf_path"], nil),
        llama_server_path: get_str(cfg, ["summarize", "llama_server_path"], nil),
        download_precompiled: get_bool(cfg, ["summarize", "download_precompiled"], true),
        launcher: get_str(cfg, ["summarize", "launcher"], nil)
      ]
    end
  end

  @doc "Returns the `[analysis]` section."
  @spec analysis() :: keyword()
  def analysis do
    cfg = load()
    [churn_max_commits: get_int(cfg, ["analysis", "churn_max_commits"], 1000)]
  end

  @doc "Returns the `[indexing]` section."
  @spec indexing() :: keyword()
  def indexing do
    cfg = load()

    [
      max_chunk_tokens: get_int(cfg, ["indexing", "max_chunk_tokens"], 512),
      ignore_dirs:
        get_list(cfg, ["indexing", "ignore_dirs"], [
          "_build",
          "deps",
          "node_modules",
          "target",
          ".git",
          "dist",
          "coverage",
          "__pycache__",
          ".elixir_ls",
          "vendor",
          "Pods",
          ".gradle",
          ".venv",
          "build",
          ".dart_tool",
          "tmp"
        ])
    ]
  end

  @doc "Returns the `[retrieval]` section."
  @spec retrieval() :: keyword()
  def retrieval do
    cfg = load()

    [
      vector_weight: get_float(cfg, ["retrieval", "vector_weight"], 0.55),
      bm25_weight: get_float(cfg, ["retrieval", "bm25_weight"], 0.25),
      graph_weight: get_float(cfg, ["retrieval", "graph_weight"], 0.20),
      top_k: get_int(cfg, ["retrieval", "top_k"], 25),
      final_k: get_int(cfg, ["retrieval", "final_k"], 7)
    ]
  end

  # ---------------------------------------------------------------------------
  # Escritura
  # ---------------------------------------------------------------------------

  @doc "Escribe la configuración completa en JSON (cifrando API keys)."
  @spec write(map()) :: :ok
  def write(sections) when is_map(sections) do
    File.mkdir_p!(cfg_dir())
    encrypted = encrypt_values(sections)
    json = Jason.encode!(encrypted, pretty: true)
    File.write!(cfg_file_path(), json <> "\n")
    :ok
  end

  @doc "Actualiza una clave concreta."
  @spec set(String.t(), String.t(), term()) :: :ok | {:error, String.t()}
  def set(section, key, value) when is_binary(section) and is_binary(key) do
    cfg = load()
    new_cfg = put_in_path(cfg, [section, key], value)
    write(new_cfg)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Ruta del fichero de configuración JSON."
  @spec config_file() :: String.t()
  def config_file, do: cfg_file_path()

  @doc """
  Reads a single top-level section from the config file. Returns a
  plain map (keys may be strings or atoms depending on caller).
  """
  @spec read_section(String.t()) :: map() | nil
  def read_section(section) when is_binary(section) do
    case load() do
      cfg when is_map(cfg) ->
        Map.get(cfg, String.to_atom(section))

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc "Ruta del legacy TOML (si existe)."
  @spec legacy_config_file() :: String.t()
  def legacy_config_file, do: legacy_toml_path()

  @doc "Contenido por defecto para `delfos config init`."
  @spec default_config_content() :: String.t()
  def default_config_content do
    Jason.encode!(@default_config, pretty: true) <> "\n"
  end

  @doc "Muestra la configuración actual (con API keys enmascaradas)."
  @spec show() :: String.t()
  def show do
    cfg_emb = embedding()
    cfg_llm = llm()
    cfg_ret = retrieval()

    # Bug #6 fix: ahora también renderizamos [analysis] e [indexing].
    # Antes solo aparecían [embedding], [llm] y [retrieval] aunque
    # existieran en config.json. Cargamos el JSON crudo para no
    # depender de getters que no existían (analysis/indexing no
    # tienen funciones de acceso dedicadas).
    raw = load_raw()

    """
    Fichero: #{cfg_file_path()}

    [embedding]
      provider   = #{cfg_emb[:provider]}
      url        = #{cfg_emb[:url]}
      model      = #{cfg_emb[:model]}
      api_key    = #{mask_key(cfg_emb[:api_key])}
      dim        = #{cfg_emb[:dim]}
      batch_size = #{cfg_emb[:batch_size]}
      timeout    = #{cfg_emb[:timeout_ms]}ms

    [llm]
      provider             = #{cfg_llm[:provider]}
      url                  = #{cfg_llm[:url]}
      model                = #{cfg_llm[:model]}
      api_key              = #{mask_key(cfg_llm[:api_key])}
      explain_max_tokens   = #{cfg_llm[:explain_max_tokens]}
      query_max_tokens     = #{cfg_llm[:query_max_tokens]}
      thinker_url          = #{cfg_llm[:thinker_url]}
      thinker_model        = #{cfg_llm[:thinker_model]}
      use_thinker_for_query= #{cfg_llm[:use_thinker_for_query]}

    #{render_section("summarize", raw["summarize"] || %{})}

    [retrieval]
      vector_weight = #{cfg_ret[:vector_weight]}
      bm25_weight   = #{cfg_ret[:bm25_weight]}
      graph_weight  = #{cfg_ret[:graph_weight]}
      top_k         = #{cfg_ret[:top_k]}
      final_k       = #{cfg_ret[:final_k]}

    #{render_section("analysis", raw["analysis"] || %{})}

    #{render_section("indexing", raw["indexing"] || %{})}
    """
  end

  # Renderiza una sección arbitraria del config como
  #   [section]
  #     key = value
  #     ...
  # Si la sección está vacía, no la incluye en el output.
  defp render_section(_name, %{} = section) when map_size(section) == 0, do: ""

  defp render_section(name, section) do
    # Salida con 2 espacios de indentación bajo [section], igual que
    # las secciones hardcoded arriba ([embedding], [llm], etc).
    lines =
      section
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map_join("\n  ", fn {k, v} -> "#{k} = #{format_value(v)}" end)

    "[#{name}]\n  #{lines}"
  end

  defp format_value(v) when is_binary(v), do: v
  defp format_value(v) when is_boolean(v), do: to_string(v)
  defp format_value(v) when is_number(v), do: to_string(v)
  defp format_value(v), do: inspect(v)

  # Lee el JSON del disco sin pasar por el pipeline de decrypt/env
  # override. Usado solo para 'show' de secciones que no tienen
  # getter dedicado (analysis, indexing).
  defp load_raw do
    config_file()
    |> File.read()
    |> case do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, parsed} -> parsed
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Privado
  # ---------------------------------------------------------------------------

  defp ensure_config_exists do
    File.mkdir_p!(cfg_dir())

    if File.exists?(legacy_toml_path()) and not File.exists?(cfg_file_path()) do
      migrate_from_toml()
    end

    unless File.exists?(cfg_file_path()) do
      write(@default_config)
    end
  end

  @doc """
  Public version of `ensure_config_exists/0` for callers that want to
  bootstrap the config file on demand (e.g. `delfos doctor --fix`).
  """
  @spec ensure_config_exists_public() :: :ok | {:error, String.t()}
  def ensure_config_exists_public do
    ensure_config_exists()
    :ok
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  @doc """
  Creates the encryption key file if it doesn't exist. Idempotent.
  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec ensure_encryption_key() :: :ok | {:error, String.t()}
  def ensure_encryption_key do
    File.mkdir_p!(cfg_dir())

    unless File.exists?(key_file_path()) do
      key = :crypto.strong_rand_bytes(32)
      hex = Base.encode16(key, case: :lower)
      File.write!(key_file_path(), hex)
      File.chmod!(key_file_path(), 0o600)
    end

    :ok
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp migrate_from_toml do
    case Toml.decode_file(legacy_toml_path()) do
      {:ok, parsed} ->
        migrated = %{
          "embedding" => %{
            "provider" => Map.get(parsed, ["embedding", "provider"], "local"),
            "url" => Map.get(parsed, ["embedding", "url"], "http://127.0.0.1:9998"),
            "model" => Map.get(parsed, ["embedding", "model"], "bge-m3"),
            "api_key" => Map.get(parsed, ["embedding", "api_key"], "sk-local-dev-key"),
            "dim" => Map.get(parsed, ["embedding", "dim"], 4096),
            "batch_size" => Map.get(parsed, ["embedding", "batch_size"], 48),
            "timeout_ms" => Map.get(parsed, ["embedding", "timeout_ms"], 25_000),
            "extra_args" => Map.get(parsed, ["embedding", "extra_args"], []),
            "gguf_path" => Map.get(parsed, ["embedding", "gguf_path"], nil),
            "llama_server_path" => Map.get(parsed, ["embedding", "llama_server_path"], nil),
            "download_precompiled" =>
              Map.get(parsed, ["embedding", "download_precompiled"], true),
            "launcher" => Map.get(parsed, ["embedding", "launcher"], nil)
          },
          "llm" => %{
            "provider" => Map.get(parsed, ["llm", "provider"], "local"),
            "url" => Map.get(parsed, ["llm", "url"], "http://127.0.0.1:8080"),
            "model" => Map.get(parsed, ["llm", "model"], "Qwen2.5-Coder-3B-Instruct"),
            "api_key" => Map.get(parsed, ["llm", "api_key"], "sk-local-dev-key"),
            "timeout_ms" => Map.get(parsed, ["llm", "timeout_ms"], 45_000),
            "summarize_max_tokens" => Map.get(parsed, ["llm", "summarize_max_tokens"], 180),
            "explain_max_tokens" => Map.get(parsed, ["llm", "explain_max_tokens"], 600),
            "query_max_tokens" => Map.get(parsed, ["llm", "query_max_tokens"], 512),
            "thinker_url" => Map.get(parsed, ["llm", "thinker_url"], "http://127.0.0.1:8081"),
            "thinker_model" => Map.get(parsed, ["llm", "thinker_model"], "thinker"),
            "use_thinker_for_query" => Map.get(parsed, ["llm", "use_thinker_for_query"], false),
            "extra_args" => Map.get(parsed, ["llm", "extra_args"], []),
            "gguf_path" => Map.get(parsed, ["llm", "gguf_path"], nil),
            "llama_server_path" => Map.get(parsed, ["llm", "llama_server_path"], nil),
            "download_precompiled" => Map.get(parsed, ["llm", "download_precompiled"], true),
            "launcher" => Map.get(parsed, ["llm", "launcher"], nil)
          },
          "retrieval" => %{
            "vector_weight" => Map.get(parsed, ["retrieval", "vector_weight"], 0.55),
            "bm25_weight" => Map.get(parsed, ["retrieval", "bm25_weight"], 0.25),
            "graph_weight" => Map.get(parsed, ["retrieval", "graph_weight"], 0.20),
            "top_k" => Map.get(parsed, ["retrieval", "top_k"], 25),
            "final_k" => Map.get(parsed, ["retrieval", "final_k"], 7)
          },
          "analysis" => %{
            "churn_max_commits" => Map.get(parsed, ["analysis", "churn_max_commits"], 1000)
          },
          "indexing" => %{
            "max_chunk_tokens" => Map.get(parsed, ["indexing", "max_chunk_tokens"], 512),
            "ignore_dirs" =>
              Map.get(
                parsed,
                ["indexing", "ignore_dirs"],
                @default_config["indexing"]["ignore_dirs"]
              )
          }
        }

        write(migrated)
        File.rename(legacy_toml_path(), legacy_toml_path() <> ".migrated")

      {:error, reason} ->
        Logger.warning("[Config.Manager] TOML migration parse error: #{inspect(reason)}")
        :ok
    end
  rescue
    e ->
      Logger.warning("[Config.Manager] TOML migration failed: #{Exception.message(e)}")
      :ok
  end

  # ── Encryption helpers ────────────────────────────────────────────────

  defp encryption_key do
    File.mkdir_p!(cfg_dir())

    unless File.exists?(key_file_path()) do
      key = :crypto.strong_rand_bytes(32)
      hex = Base.encode16(key, case: :lower)
      File.write!(key_file_path(), hex)
      File.chmod!(key_file_path(), 0o600)
    end

    key_file_path()
    |> File.read!()
    |> String.trim()
    |> Base.decode16!(case: :mixed)
  end

  defp encrypt_values(map) when is_map(map) do
    key = encryption_key()

    Map.new(map, fn {k, value} ->
      {k, encrypt_node(value, key)}
    end)
  end

  defp encrypt_node(value, key) when is_map(value) do
    Map.new(value, fn {k, v} ->
      if is_api_key_field?(k) and is_binary(v) and not already_encrypted?(v) do
        {:ok, encrypted} = Apero.Crypto.Cipher.encrypt(v, key)
        {k, "enc:" <> encrypted}
      else
        {k, v}
      end
    end)
  end

  defp encrypt_node(value, _key), do: value

  defp already_encrypted?("enc:" <> _), do: true
  defp already_encrypted?(_), do: false

  defp decrypt_values(map) when is_map(map) do
    key = encryption_key()

    Map.new(map, fn {k, value} ->
      {k, decrypt_node(value, key)}
    end)
  end

  defp decrypt_node(value, key) when is_map(value) do
    Map.new(value, fn {k, v} ->
      if is_api_key_field?(k) and is_binary(v) do
        {k, decrypt_value(v, key)}
      else
        {k, v}
      end
    end)
  end

  defp decrypt_node(value, _key), do: value

  defp decrypt_value("enc:" <> encoded, key) do
    case Apero.Crypto.Cipher.decrypt(encoded, key) do
      {:ok, plain} -> plain
      {:error, _} -> "invalid-encrypted-value"
    end
  end

  defp decrypt_value(value, _key), do: value

  defp is_api_key_field?("api_key"), do: true
  defp is_api_key_field?(_), do: false

  # ── Env overrides ─────────────────────────────────────────────────────

  defp apply_env_overrides(cfg) do
    overrides = [
      {"DELFOS_EMBED_PROVIDER", ["embedding", "provider"]},
      {"EMBED_URL", ["embedding", "url"]},
      {"EMBED_MODEL", ["embedding", "model"]},
      {"EMBED_API_KEY", ["embedding", "api_key"]},
      {"EMBED_DIM", ["embedding", "dim"]},
      {"DELFOS_LLM_PROVIDER", ["llm", "provider"]},
      {"LLAMA_URL", ["llm", "url"]},
      {"LLM_MODEL", ["llm", "model"]},
      {"LLM_API_KEY", ["llm", "api_key"]},
      {"THINKER_URL", ["llm", "thinker_url"]},
      {"THINKER_MODEL", ["llm", "thinker_model"]},
      {"USE_THINKER", ["llm", "use_thinker_for_query"]},
      {"DELFOS_SUMMARIZE_PROVIDER", ["summarize", "provider"]},
      {"SUMMARIZE_URL", ["summarize", "url"]},
      {"SUMMARIZE_MODEL", ["summarize", "model"]},
      {"SUMMARIZE_API_KEY", ["summarize", "api_key"]},
      {"SUMMARIZE_MAX_TOKENS", ["summarize", "max_tokens"]}
    ]

    Enum.reduce(overrides, cfg, fn {env_var, path}, acc ->
      case System.get_env(env_var) do
        nil -> acc
        value -> put_in_path(acc, path, value)
      end
    end)
  end

  defp put_in_path(map, [key], value), do: Map.put(map, key, value)

  defp put_in_path(map, [section | rest], value) do
    sub = Map.get(map, section, %{})
    Map.put(map, section, put_in_path(sub, rest, value))
  end

  # ── Getters ───────────────────────────────────────────────────────────

  defp get_str(cfg, path, default) do
    case get_in(cfg, path) do
      nil -> default
      v -> to_string(v)
    end
  end

  defp get_int(cfg, path, default) do
    case get_in(cfg, path) do
      nil -> default
      v when is_integer(v) -> v
      v -> String.to_integer(to_string(v))
    end
  end

  defp get_float(cfg, path, default) do
    case get_in(cfg, path) do
      nil -> default
      v when is_float(v) -> v
      v when is_integer(v) -> v / 1.0
      v -> String.to_float(to_string(v))
    end
  end

  defp get_bool(cfg, path, default) do
    case get_in(cfg, path) do
      nil -> default
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp get_atom(cfg, path, default) do
    case get_in(cfg, path) do
      nil ->
        default

      v ->
        str = to_string(v)

        try do
          String.to_existing_atom(str)
        rescue
          ArgumentError -> default
        end
    end
  end

  defp get_list(cfg, path, default) do
    case get_in(cfg, path) do
      nil -> default
      v when is_list(v) -> v
      _ -> default
    end
  end

  defp mask_key(nil), do: "(no configurada)"
  defp mask_key(key) when byte_size(key) <= 8, do: String.duplicate("*", byte_size(key))
  defp mask_key(key), do: String.slice(key, 0, 6) <> "..." <> String.slice(key, -4, 4)
end
