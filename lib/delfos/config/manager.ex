defmodule Delfos.Config.Manager do
  @moduledoc """
  Gestiona la configuración global de Delfos en ~/.config/delfos/delfos.conf

  El fichero usa formato TOML. Si no existe se crea con valores por defecto.
  Soporta tres tipos de proveedores para LLM y embeddings:
    - :local     — llama-server / text-embeddings-inference (OpenAI-compatible)
    - :openai    — OpenAI API
    - :anthropic — Anthropic API (Claude)

  Variables de entorno tienen precedencia sobre el fichero de config.
  """

  @config_dir Path.expand("~/.config/delfos")
  @config_file Path.join(@config_dir, "delfos.conf")

  @default_config """
  # Delfos global configuration
  # ~/.config/delfos/delfos.conf
  # Edit with: delfos config set <section> <key> <value>

  [embedding]
  provider   = "local"
  url        = "http://127.0.0.1:9998"
  model      = "bge-m3"
  api_key    = "sk-local-dev"
  dim        = 1024
  batch_size = 48
  timeout_ms = 25000

  # BGE-M3 recommended startup:
  # llama-server -m bge-m3-q4_k_m.gguf --port 9998 --embedding \\
  #   --threads 4 --batch-size 64 --ctx-size 2048 \\
  #   --mlock --no-mmap --flash-attn --host 127.0.0.1

  [llm]
  provider           = "local"
  url                = "http://127.0.0.1:8080"
  model              = "Qwen2.5-Coder-3B-Instruct"
  api_key            = "sk-local-dev"
  timeout_ms         = 45000
  summarize_max_tokens = 180
  explain_max_tokens   = 600
  query_max_tokens     = 512
  # Optional: thinker (larger model) for query/explain quality
  thinker_url        = "http://127.0.0.1:8081"
  thinker_model      = "thinker"
  use_thinker_for_query = false

  # Qwen2.5-Coder-3B recommended startup:
  # llama-server -m qwen2.5-coder-3b-instruct-q4_k_m.gguf --port 8080 \\
  #   --threads 6 --batch-size 128 --ctx-size 8192 \\
  #   --mlock --no-mmap --flash-attn --host 127.0.0.1

  # Anthropic example:
  # provider  = "anthropic"
  # url       = "https://api.anthropic.com"
  # model     = "claude-sonnet-4-20250514"
  # api_key   = "sk-ant-..."

  # OpenAI example:
  # provider  = "openai"
  # url       = "https://api.openai.com"
  # model     = "gpt-4o-mini"
  # api_key   = "sk-..."

  [retrieval]
  vector_weight = 0.55
  bm25_weight   = 0.25
  graph_weight  = 0.20
  top_k         = 25
  final_k       = 7

  [analysis]
  churn_max_commits = 1000

  [indexing]
  max_chunk_tokens = 512
  ignore_dirs = ["_build", "deps", "node_modules", "target", ".git", "dist",
                 "coverage", "__pycache__", ".elixir_ls", "vendor", "Pods",
                 ".gradle", ".venv", "build", ".dart_tool"]
  """

  # ---------------------------------------------------------------------------
  # Lectura
  # ---------------------------------------------------------------------------

  def load do
    ensure_config_exists()

    base =
      case Toml.decode_file(@config_file) do
        {:ok, parsed} -> parsed
        {:error, _} -> default_map()
      end

    apply_env_overrides(base)
  end

  def embedding do
    cfg = load()

    [
      provider: get_atom(cfg, ["embedding", "provider"], :local),
      url: get_str(cfg, ["embedding", "url"], "http://127.0.0.1:9998"),
      model: get_str(cfg, ["embedding", "model"], "bge-m3"),
      api_key: get_str(cfg, ["embedding", "api_key"], "sk-local-dev"),
      dim: get_int(cfg, ["embedding", "dim"], 1024),
      batch_size: get_int(cfg, ["embedding", "batch_size"], 48),
      timeout_ms: get_int(cfg, ["embedding", "timeout_ms"], 25_000)
    ]
  end

  def llm do
    cfg = load()

    [
      provider: get_atom(cfg, ["llm", "provider"], :local),
      url: get_str(cfg, ["llm", "url"], "http://127.0.0.1:8080"),
      model: get_str(cfg, ["llm", "model"], "Qwen2.5-Coder-3B-Instruct"),
      api_key: get_str(cfg, ["llm", "api_key"], "sk-local-dev"),
      timeout_ms: get_int(cfg, ["llm", "timeout_ms"], 45_000),
      summarize_max_tokens: get_int(cfg, ["llm", "summarize_max_tokens"], 180),
      explain_max_tokens: get_int(cfg, ["llm", "explain_max_tokens"], 600),
      query_max_tokens: get_int(cfg, ["llm", "query_max_tokens"], 512),
      thinker_url: get_str(cfg, ["llm", "thinker_url"], "http://127.0.0.1:8081"),
      thinker_model: get_str(cfg, ["llm", "thinker_model"], "thinker"),
      use_thinker_for_query: get_bool(cfg, ["llm", "use_thinker_for_query"], false)
    ]
  end

  def analysis do
    cfg = load()
    [churn_max_commits: get_int(cfg, ["analysis", "churn_max_commits"], 1000)]
  end

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
          ".dart_tool"
        ])
    ]
  end

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

  def set(section, key, value) when is_binary(section) and is_binary(key) do
    ensure_config_exists()
    content = File.read!(@config_file)

    pattern = ~r/(\[#{Regex.escape(section)}\][^\[]*?\n#{Regex.escape(key)}\s*=\s*)[^\n]*/s

    new_content =
      if Regex.match?(pattern, content) do
        Regex.replace(pattern, content, "\\1#{format_value(value)}", global: false)
      else
        section_pattern = ~r/(\[#{Regex.escape(section)}\][^\[]*)/s

        if Regex.match?(section_pattern, content) do
          Regex.replace(section_pattern, content, "\\1#{key} = #{format_value(value)}\n",
            global: false
          )
        else
          content <> "\n[#{section}]\n#{key} = #{format_value(value)}\n"
        end
      end

    File.write!(@config_file, new_content)
    :ok
  end

  def config_file, do: @config_file

  def show do
    ensure_config_exists()
    cfg_emb = embedding()
    cfg_llm = llm()
    cfg_ret = retrieval()

    """
    Fichero: #{@config_file}

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
      summarize_max_tokens = #{cfg_llm[:summarize_max_tokens]}
      explain_max_tokens   = #{cfg_llm[:explain_max_tokens]}
      query_max_tokens     = #{cfg_llm[:query_max_tokens]}
      thinker_url          = #{cfg_llm[:thinker_url]}
      thinker_model        = #{cfg_llm[:thinker_model]}
      use_thinker_for_query= #{cfg_llm[:use_thinker_for_query]}

    [retrieval]
      vector_weight = #{cfg_ret[:vector_weight]}
      bm25_weight   = #{cfg_ret[:bm25_weight]}
      graph_weight  = #{cfg_ret[:graph_weight]}
      top_k         = #{cfg_ret[:top_k]}
      final_k       = #{cfg_ret[:final_k]}
    """
  end

  # ---------------------------------------------------------------------------
  # Privado
  # ---------------------------------------------------------------------------

  defp ensure_config_exists do
    File.mkdir_p!(@config_dir)
    unless File.exists?(@config_file), do: File.write!(@config_file, @default_config)
  end

  defp default_map do
    case Toml.decode(@default_config) do
      {:ok, m} -> m
      _ -> %{}
    end
  end

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
      {"API_KEY", ["embedding", "api_key"]},
      {"API_KEY", ["llm", "api_key"]}
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
      _ -> default
    end
  end

  defp get_atom(cfg, path, default) do
    case get_in(cfg, path) do
      nil -> default
      v -> v |> to_string() |> String.to_atom()
    end
  end

  defp get_list(cfg, path, default) do
    case get_in(cfg, path) do
      nil -> default
      v when is_list(v) -> v
      _ -> default
    end
  end

  defp format_value(v) when is_binary(v), do: ~s("#{v}")
  defp format_value(v) when is_integer(v), do: to_string(v)
  defp format_value(v) when is_atom(v), do: ~s("#{v}")
  defp format_value(v), do: inspect(v)

  defp mask_key(nil), do: "(no configurada)"
  defp mask_key(key) when byte_size(key) <= 8, do: String.duplicate("*", byte_size(key))
  defp mask_key(key), do: String.slice(key, 0, 6) <> "..." <> String.slice(key, -4, 4)
end
