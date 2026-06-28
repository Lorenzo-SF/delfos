defmodule Delfos.CLI.Commands.Setup.LLM do
  @moduledoc """
  Interactive LLM setup for Delfos.

  Guides the user through:
    1. Choose provider: llama.cpp / Ollama / External
    2. Configure per provider (paths, models, endpoints)
    3. Write config.json with encrypted API keys
  """

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive
  alias Delfos.Config.Manager

  @embedding_models [
    %{
      id: :bge_m3,
      label: "BGE-M3 (multilingual, 1024d, 8192 ctx) — recommended",
      filename: "bge-m3-Q4_K_M.gguf",
      url: "https://huggingface.co/bartowski/bge-m3-GGUF/resolve/main/bge-m3-Q4_K_M.gguf",
      dim: 1024
    },
    %{
      id: :mxbai,
      label: "mxbai-embed-large (English, 1024d) — fast",
      filename: "mxbai-embed-large-v1-Q4_K_M.gguf",
      url:
        "https://huggingface.co/bartowski/mxbai-embed-large-v1-GGUF/resolve/main/mxbai-embed-large-v1-Q4_K_M.gguf",
      dim: 1024
    },
    %{
      id: :nomic,
      label: "nomic-embed-text (English, 768d) — lightweight",
      filename: "nomic-embed-text-v1.5-Q4_K_M.gguf",
      url:
        "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5-Q4_K_M.gguf",
      dim: 768
    },
    %{
      id: :all_minilm,
      label: "all-MiniLM-L6-v2 (English, 384d) — minimal",
      filename: "all-MiniLM-L6-v2-Q4_K_M.gguf",
      url:
        "https://huggingface.co/mezima/all-MiniLM-L6-v2-Q4_K_M-GGUF/resolve/main/all-MiniLM-L6-v2-Q4_K_M.gguf",
      dim: 384
    }
  ]

  @llm_models [
    %{
      id: :qwen_coder_3b,
      label: "Qwen2.5-Coder-3B-Instruct (~2.2GB) — recommended",
      filename: "qwen2.5-coder-3b-instruct-q4_k_m.gguf",
      url:
        "https://huggingface.co/bartowski/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-3B-Instruct-Q4_K_M.gguf",
      port: 8080
    },
    %{
      id: :llama_3b,
      label: "Llama-3.2-3B-Instruct (~2GB) — general purpose",
      filename: "llama-3.2-3b-instruct-q4_k_m.gguf",
      url:
        "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
      port: 8080
    },
    %{
      id: :qwen_coder_7b,
      label: "Qwen2.5-Coder-7B-Instruct (~4.5GB) — better quality",
      filename: "qwen2.5-coder-7b-instruct-q4_k_m.gguf",
      url:
        "https://huggingface.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf",
      port: 8080
    },
    %{
      id: :deepseek_coder,
      label: "DeepSeek-Coder-V2-Lite-Instruct (~4GB)",
      filename: "deepseek-coder-v2-lite-instruct-q4_k_m.gguf",
      url:
        "https://huggingface.co/bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf",
      port: 8080
    }
  ]

  def run(opts \\ []) do
    cfg = Manager.llm()
    embed_cfg = Manager.embedding()
    force = opts[:force] || false

    if configured?(cfg) and not force do
      Alaja.print_success("LLM: #{cfg[:url]} · #{cfg[:model]}")
      Alaja.print_success("Embedding: #{embed_cfg[:url]} · dim=#{embed_cfg[:dim]}")

      case Interactive.question_with_options(
             "LLM is already configured. What do you want to do?",
             [
               {"1. Keep current configuration", :keep},
               {"2. Re-configure from scratch (change provider/models)", :reconfig}
             ],
             color: :cyan
           ) do
        :keep -> true
        :reconfig -> start_wizard()
        :error -> true
      end
    else
      start_wizard()
    end
  rescue
    _ -> start_wizard()
  end

  defp start_wizard do
    Header.print("LLM setup", subtitle: "Choose how Delfos runs AI models", size: :small)
    Alaja.print_raw("\n")
    choose_provider()
  end

  defp configured?(cfg), do: cfg[:url] && cfg[:url] != "" && cfg[:url] != "http://"

  # ── Provider choice ────────────────────────────────────────────────────

  defp choose_provider do
    case Interactive.question_with_options(
           "Which engine / provider?",
           [
             {"1. llama.cpp — download GGUF or use local files, run llama-server", :llama_cpp},
             {"2. Ollama — use running Ollama daemon (localhost:11434)", :ollama},
             {"3. External API — OpenAI, Anthropic, or compatible", :external},
             {"n. Skip — I'll configure later", :skip}
           ],
           color: :cyan
         ) do
      :llama_cpp ->
        setup_llama_cpp()

      :ollama ->
        setup_ollama()

      :external ->
        setup_external()

      :skip ->
        skip_msg()

      :error ->
        Alaja.print_error("No valid option")
        false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # llama.cpp
  # ═══════════════════════════════════════════════════════════════════════

  defp setup_llama_cpp do
    Alaja.print_raw("\n")
    Header.print("llama.cpp setup", subtitle: "GGUF model files", size: :small)
    Alaja.print_raw("\n")

    gguf_path = ask_gguf_path()
    emb = pick_embedding_model(gguf_path)
    llm = pick_llm_model(gguf_path)

    if emb && llm do
      Alaja.print_raw("\n")
      config = build_llama_cpp_config(emb, llm, gguf_path)
      Manager.write(config)
      Alaja.print_success("Configuration saved to #{Manager.config_file()}")
      Alaja.print_raw("\n")
      print_launch_instructions(emb, llm, gguf_path)
      true
    else
      skip_msg()
    end
  end

  defp ask_gguf_path do
    default = "~/.delfos/models"

    answer =
      Interactive.question("Path for GGUF files [#{default}]:", color: :cyan)
      |> String.trim()

    if answer == "", do: Path.expand(default), else: Path.expand(answer)
  end

  # ── Model picker — llama.cpp ──────────────────────────────────────────

  defp pick_embedding_model(gguf_dir) do
    existing = scan_ggufs(gguf_dir)

    pick_model(
      :embedding,
      @embedding_models,
      existing,
      "Embedding model",
      "For semantic code search"
    )
  end

  defp pick_llm_model(gguf_dir) do
    existing = scan_ggufs(gguf_dir)
    pick_model(:llm, @llm_models, existing, "LLM model", "For code summarization and analysis")
  end

  defp scan_ggufs(dir) do
    if File.dir?(dir) do
      case File.ls(dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".gguf"))
          |> Enum.map(fn f -> %{path: Path.join(dir, f), filename: f} end)

        _ ->
          []
      end
    else
      []
    end
  end

  defp pick_model(_type, predefined, existing, title, subtitle) do
    Header.print(title, subtitle: subtitle, size: :small)

    options = build_model_options(predefined, existing)

    case Interactive.question_with_options("Which model?\n\nYour choice", options,
           color: :magenta
         ) do
      :skip ->
        nil

      {:existing, file} ->
        file

      {:custom_url, url} ->
        name =
          Interactive.question("Model filename (e.g. my-model-q4_k_m.gguf):", color: :cyan)
          |> String.trim()

        if name != "", do: %{filename: name, url: url, dim: 1024, port: 8080}, else: nil

      id ->
        Enum.find(predefined, &(&1.id == id))
    end
  end

  defp build_model_options(predefined, existing) do
    opts =
      predefined
      |> Enum.with_index(1)
      |> Enum.map(fn {m, i} -> {"#{i}. #{m.label} (download)", m.id} end)

    opts =
      if existing != [] do
        files =
          existing
          |> Enum.with_index(length(predefined) + 1)
          |> Enum.map(fn {f, i} -> {"#{i}. #{f.filename} (local)", {:existing, f}} end)

        opts ++ files
      else
        opts
      end

    next = length(predefined) + length(existing) + 1

    opts ++
      [
        {"#{next}. Custom GGUF URL (HuggingFace or direct)", {:custom_url, nil}},
        {"n. None — skip", :skip}
      ]
  end

  # ── llama.cpp config ──────────────────────────────────────────────────

  defp build_llama_cpp_config(emb, llm, gguf_dir) do
    emb_name = model_name(emb)
    llm_name = model_name(llm)
    emb_path = model_path(emb, gguf_dir)
    llm_path = model_path(llm, gguf_dir)

    %{
      "embedding" => %{
        "provider" => "local",
        "url" => "http://127.0.0.1:9998",
        "model" => emb_name,
        "api_key" => "sk-local-dev",
        "dim" => emb[:dim] || 1024,
        "batch_size" => 32,
        "timeout_ms" => 30_000,
        "gguf_path" => emb_path
      },
      "llm" => %{
        "provider" => "local",
        "url" => "http://127.0.0.1:#{llm[:port] || 8080}",
        "model" => llm_name,
        "api_key" => "sk-local-dev",
        "timeout_ms" => 45_000,
        "summarize_max_tokens" => 180,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512,
        "gguf_path" => llm_path
      },
      "retrieval" => %{
        "vector_weight" => 0.55,
        "bm25_weight" => 0.25,
        "graph_weight" => 0.20,
        "top_k" => 25,
        "final_k" => 7
      },
      "indexing" => %{
        "max_chunk_tokens" => 512
      }
    }
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Ollama
  # ═══════════════════════════════════════════════════════════════════════

  defp setup_ollama do
    Alaja.print_raw("\n")
    Header.print("Ollama setup", subtitle: "Connect to running Ollama daemon", size: :small)
    Alaja.print_raw("\n")

    url = ask_ollama_url()

    case probe_ollama(url) do
      {:ok, models} ->
        emb = pick_ollama_model(models, "Embedding model")
        llm = pick_ollama_model(models, "LLM model")

        if emb && llm do
          dim = detect_ollama_dim(url, emb)
          config = build_ollama_config(url, emb, llm, dim)
          Manager.write(config)
          Alaja.print_success("Ollama configuration saved to #{Manager.config_file()}")
          true
        else
          skip_msg()
        end

      {:error, reason} ->
        Alaja.print_warning("Ollama not reachable: #{reason}")
        Alaja.print_raw("\n")

        case Interactive.yesno("Try llama.cpp instead?", default: :yes) do
          :yes -> setup_llama_cpp()
          :no -> skip_msg()
        end
    end
  end

  defp ask_ollama_url do
    answer =
      Interactive.question("Ollama URL [http://localhost:11434]:", color: :cyan)
      |> String.trim()

    if answer == "", do: "http://localhost:11434", else: answer
  end

  defp probe_ollama(url) do
    case Req.get("#{url}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: s, body: %{"models" => models}}} when s in 200..299 ->
        names = Enum.map(models, fn m -> m["name"] end)

        if names == [] do
          Alaja.print_info("Ollama is running but has no models installed.")
        end

        {:ok, names}

      {:ok, %{status: s}} ->
        {:error, "HTTP #{s}"}

      {:error, _} ->
        {:error, "Connection refused — is Ollama running?"}
    end
  rescue
    _ -> {:error, "Connection failed"}
  end

  defp pick_ollama_model([], _label) do
    name =
      Interactive.question("Model name (ollama pull <name>):", color: :cyan)
      |> String.trim()

    if name != "" do
      pull_ollama_model(name)
      name
    end
  end

  defp pick_ollama_model(models, label) do
    Header.print(label, subtitle: "Available in Ollama", size: :small)

    options =
      models
      |> Enum.with_index(1)
      |> Enum.map(fn {m, i} -> {"#{i}. #{m}", m} end)

    options = options ++ [{"c. Custom model name", :custom}, {"n. None — skip", :skip}]

    case Interactive.question_with_options("Which model?\n\nYour choice", options,
           color: :magenta
         ) do
      :skip ->
        nil

      :custom ->
        name =
          Interactive.question("Model name (ollama pull <name>):", color: :cyan)
          |> String.trim()

        if name != "" do
          pull_ollama_model(name)
          name
        end

      name when is_binary(name) ->
        name
    end
  end

  defp pull_ollama_model(name) do
    Alaja.print_info("Pulling #{name} from Ollama library...")

    case System.cmd("ollama", ["pull", name], stderr_to_stdout: true) do
      {_, 0} -> Alaja.print_success("#{name} pulled")
      {err, _} -> Alaja.print_warning("Pull issue: #{String.slice(err, 0, 200)}")
    end
  rescue
    _ -> Alaja.print_warning("Could not run 'ollama pull'. Install Ollama first.")
  end

  defp detect_ollama_dim(url, model) do
    case Req.post("#{url}/api/embed",
           json: %{model: model, input: "test"},
           receive_timeout: 10_000
         ) do
      {:ok, %{body: %{"embeddings" => [vec | _]}}} -> length(vec)
      _ -> 1024
    end
  rescue
    _ -> 1024
  end

  defp build_ollama_config(url, emb, llm, dim) do
    %{
      "embedding" => %{
        "provider" => "ollama",
        "url" => url,
        "model" => emb,
        "api_key" => "sk-local-dev",
        "dim" => dim,
        "batch_size" => 32,
        "timeout_ms" => 30_000
      },
      "llm" => %{
        "provider" => "ollama",
        "url" => url,
        "model" => llm,
        "api_key" => "sk-local-dev",
        "timeout_ms" => 45_000,
        "summarize_max_tokens" => 180,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512
      },
      "retrieval" => %{
        "vector_weight" => 0.55,
        "bm25_weight" => 0.25,
        "graph_weight" => 0.20,
        "top_k" => 25,
        "final_k" => 7
      },
      "indexing" => %{
        "max_chunk_tokens" => 512
      }
    }
  end

  # ═══════════════════════════════════════════════════════════════════════
  # External API (OpenAI / Anthropic / compatible)
  # ═══════════════════════════════════════════════════════════════════════

  defp setup_external do
    Alaja.print_raw("\n")
    Header.print("External API setup", subtitle: "OpenAI, Anthropic, or compatible", size: :small)
    Alaja.print_raw("\n")

    base_url =
      Interactive.question("Base URL:", color: :cyan) |> String.trim()

    api_key =
      Interactive.question("API key:", color: :cyan) |> String.trim()

    Alaja.print_info("Probing API to detect provider type...")

    case probe_provider(base_url, api_key) do
      :openai ->
        Alaja.print_success("Detected: OpenAI-compatible API")
        configure_external(base_url, api_key)

      :anthropic ->
        Alaja.print_success("Detected: Anthropic-compatible API")
        configure_external_anthropic(base_url, api_key)

      {:error, reason} ->
        Alaja.print_warning("Could not detect provider type: #{reason}")
        Alaja.print_raw("\n")

        case Interactive.question_with_options(
               "Which provider type is this?",
               [
                 {"1. OpenAI-compatible (Groq, Together, vLLM, etc.)", :openai},
                 {"2. Anthropic-compatible", :anthropic},
                 {"3. Back — try again", :back}
               ],
               color: :cyan
             ) do
          :openai -> configure_external(base_url, api_key)
          :anthropic -> configure_external_anthropic(base_url, api_key)
          :back -> setup_external()
          :error -> skip_msg()
        end
    end
  end

  defp probe_provider(base_url, api_key) do
    emb_model = "text-embedding-3-small"

    probe = fn ->
      Req.post("#{base_url}/v1/embeddings",
        json: %{model: emb_model, input: "ping"},
        headers: [{"authorization", "Bearer #{api_key}"}],
        receive_timeout: 5_000
      )
    end

    case probe.() do
      {:ok, %{status: s}} when s in 200..299 ->
        :openai

      {:ok, %{status: 404}} ->
        case Req.post("#{base_url}/v1/messages",
               json: %{
                 model: "claude-sonnet-4-20250514",
                 max_tokens: 1,
                 messages: [%{role: "user", content: "hi"}]
               },
               headers: [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
               receive_timeout: 5_000
             ) do
          {:ok, %{status: s}} when s in 200..299 -> :anthropic
          {:ok, %{status: s}} -> {:error, "HTTP #{s} — not OpenAI or Anthropic"}
          {:error, r} -> {:error, "Anthropic probe failed: #{inspect(r)}"}
        end

      {:ok, %{status: s}} ->
        {:error, "HTTP #{s}"}

      {:error, r} ->
        {:error, "Connection failed: #{inspect(r)}"}
    end
  rescue
    e -> {:error, "Probe raised: #{Exception.message(e)}"}
  end

  defp configure_external(base_url, api_key) do
    emb =
      Interactive.question("Embedding model [text-embedding-3-small]:", color: :cyan)
      |> String.trim()

    emb = if emb == "", do: "text-embedding-3-small", else: emb

    llm =
      Interactive.question("Chat model [gpt-4o]:", color: :cyan)
      |> String.trim()

    llm = if llm == "", do: "gpt-4o", else: llm

    dim_str =
      Interactive.question("Embedding dimensions [1024]:", color: :cyan)
      |> String.trim()

    dim = if dim_str == "", do: 1024, else: String.to_integer(dim_str)

    port_str =
      Interactive.question("Port [443]:", color: :cyan) |> String.trim()

    port = if port_str == "", do: 443, else: String.to_integer(port_str)

    config = build_external_openai_config(base_url, port, api_key, emb, llm, dim)
    Manager.write(config)
    Alaja.print_success("External API configuration saved to #{Manager.config_file()}")
    true
  end

  defp configure_external_anthropic(base_url, api_key) do
    llm =
      Interactive.question("Chat model [claude-sonnet-4-20250514]:", color: :cyan)
      |> String.trim()

    llm = if llm == "", do: "claude-sonnet-4-20250514", else: llm

    port_str =
      Interactive.question("Port [443]:", color: :cyan) |> String.trim()

    port = if port_str == "", do: 443, else: String.to_integer(port_str)

    config = build_external_anthropic_config(base_url, port, api_key, llm)
    Manager.write(config)
    Alaja.print_success("Anthropic configuration saved to #{Manager.config_file()}")
    true
  end

  defp build_external_openai_config(base_url, port, api_key, emb, llm, dim) do
    %{
      "embedding" => %{
        "provider" => "openai",
        "url" => "#{base_url}:#{port}",
        "model" => emb,
        "api_key" => api_key,
        "dim" => dim,
        "batch_size" => 32,
        "timeout_ms" => 30_000
      },
      "llm" => %{
        "provider" => "openai",
        "url" => "#{base_url}:#{port}",
        "model" => llm,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "summarize_max_tokens" => 180,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512
      },
      "retrieval" => %{
        "vector_weight" => 0.55,
        "bm25_weight" => 0.25,
        "graph_weight" => 0.20,
        "top_k" => 25,
        "final_k" => 7
      },
      "indexing" => %{
        "max_chunk_tokens" => 512
      }
    }
  end

  defp build_external_anthropic_config(base_url, port, api_key, llm) do
    %{
      "embedding" => %{
        "provider" => "openai",
        "url" => "https://api.openai.com",
        "model" => "text-embedding-3-small",
        "api_key" => "needs-openai-key",
        "dim" => 1024,
        "batch_size" => 32,
        "timeout_ms" => 30_000
      },
      "llm" => %{
        "provider" => "anthropic",
        "url" => "#{base_url}:#{port}",
        "model" => llm,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "summarize_max_tokens" => 180,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512
      },
      "retrieval" => %{
        "vector_weight" => 0.55,
        "bm25_weight" => 0.25,
        "graph_weight" => 0.20,
        "top_k" => 25,
        "final_k" => 7
      },
      "indexing" => %{
        "max_chunk_tokens" => 512
      }
    }
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════════════

  defp model_name(%{path: path}) do
    path |> Path.basename() |> String.replace(~r/\.gguf$/, "")
  end

  defp model_name(%{filename: fname}) do
    String.replace(fname, ~r/\.gguf$/, "")
  end

  defp model_path(%{path: path}, _gguf_dir), do: path
  defp model_path(%{filename: fname}, gguf_dir), do: Path.join(gguf_dir, fname)

  defp print_launch_instructions(emb, llm, gguf_dir) do
    emb_path = model_path(emb, gguf_dir)
    llm_path = model_path(llm, gguf_dir)
    llm_port = emb[:port] || llm[:port] || 8080

    Alaja.print_raw("\n")

    Header.print("Next: launch the servers",
      subtitle: "Run these in separate terminals",
      size: :small
    )

    Alaja.print_raw("\n")

    if File.exists?(emb_path) do
      Alaja.print_info("Terminal 1 — Embedding server:")
      Alaja.print_raw("  llama-server -m #{emb_path} --port 9998 --embedding")
      Alaja.print_raw(" --threads 4 --batch-size 64 --ctx-size 2048 --mlock --host 127.0.0.1\n")
      Alaja.print_raw("\n")
    else
      Alaja.print_info("Embedding model not found at #{emb_path}")
      Alaja.print_raw("  Download it or place the GGUF file there, then run:\n")
      Alaja.print_raw("  delfos doctor\n\n")
    end

    if File.exists?(llm_path) do
      Alaja.print_info("Terminal 2 — LLM server:")
      Alaja.print_raw("  llama-server -m #{llm_path} --port #{llm_port}")
      Alaja.print_raw(" --threads 6 --batch-size 128 --ctx-size 8192 --mlock --host 127.0.0.1\n")
      Alaja.print_raw("\n")
    else
      Alaja.print_info("LLM model not found at #{llm_path}")
      Alaja.print_raw("  Download it or place the GGUF file there, then run:\n")
      Alaja.print_raw("  delfos doctor\n\n")
    end

    Alaja.print_info("After both are running:")
    Alaja.print_raw("  delfos doctor\n")
  end

  defp skip_msg do
    Alaja.print_info("LLM setup skipped. Run 'delfos doctor --fix' to complete later.")
    false
  end
end
