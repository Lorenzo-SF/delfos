defmodule Delfos.CLI.Commands.Setup.LLM.LlamaCpp do
  @moduledoc false

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive
  alias Delfos.CLI.Commands.Setup.LLM

  @default_host "127.0.0.1"
  @default_api_key "sk-local-dev-key"
  @default_model_dir "~/.delfos/models"

  @known_models %{
    embedding: [
      %{
        filename: "bge-m3-Q4_K_M.gguf",
        url: "https://huggingface.co/bartowski/bge-m3-GGUF/resolve/main/bge-m3-Q4_K_M.gguf",
        dim: 1024
      },
      %{
        filename: "mxbai-embed-large-v1-Q4_K_M.gguf",
        url:
          "https://huggingface.co/bartowski/mxbai-embed-large-v1-GGUF/resolve/main/mxbai-embed-large-v1-Q4_K_M.gguf",
        dim: 1024
      },
      %{
        filename: "nomic-embed-text-v1.5-Q4_K_M.gguf",
        url:
          "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5-Q4_K_M.gguf",
        dim: 768
      },
      %{
        filename: "all-MiniLM-L6-v2-Q4_K_M.gguf",
        url:
          "https://huggingface.co/mezima/all-MiniLM-L6-v2-Q4_K_M-GGUF/resolve/main/all-MiniLM-L6-v2-Q4_K_M.gguf",
        dim: 384
      }
    ],
    llm: [
      %{
        filename: "Qwen2.5-Coder-3B-Instruct-Q4_K_M.gguf",
        url:
          "https://huggingface.co/bartowski/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-3B-Instruct-Q4_K_M.gguf"
      },
      %{
        filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        url:
          "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
      },
      %{
        filename: "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf",
        url:
          "https://huggingface.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"
      },
      %{
        filename: "DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf",
        url:
          "https://huggingface.co/bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf"
      }
    ]
  }

  @doc false
  def run(%{target: :both} = opts) do
    embedding_ok = run(%{opts | target: :embedding})
    llm_ok = run(%{opts | target: :llm})
    embedding_ok and llm_ok
  end

  def run(%{target: target}) when target in [:llm, :embedding] do
    Alaja.print_raw("\n")

    Header.print("llama.cpp #{target_label(target)} setup",
      subtitle: "Local GGUF model served through Candil",
      size: :small
    )

    Alaja.print_raw("\n")

    with {:ok, answers} <- ask_config(target),
         :ok <- persist_and_register(target, answers) do
      Alaja.print_success("#{target_label(target)} configuration saved")
      true
    else
      :skip ->
        skip_msg()

      {:error, reason} ->
        Alaja.print_error("llama.cpp setup failed: #{inspect(reason)}")
        false
    end
  end

  @doc false
  def scan_ggufs(dir) do
    if File.dir?(dir) do
      case File.ls(dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".gguf"))
          |> Enum.sort()
          |> Enum.map(fn file -> %{path: Path.join(dir, file), filename: file} end)

        _ ->
          []
      end
    else
      []
    end
  end

  defp ask_config(target) do
    with {:ok, host} <- ask_host(),
         {:ok, port} <- ask_port(target),
         {:ok, api_key} <- ask_api_key(),
         {:ok, gguf_dir} <- ask_gguf_dir(),
         {:ok, gguf} <- ask_gguf_file(target, gguf_dir),
         {:ok, server} <- ask_llama_server_path(),
         {:ok, launcher} <- ask_launcher(),
         {:ok, extra_args} <- ask_extra_args(),
         {:ok, context_size} <- ask_context_size(gguf.path),
         {:ok, download_model?} <- ask_download_model() do
      {:ok,
       %{
         host: host,
         port: port,
         api_key: api_key,
         gguf_dir: gguf_dir,
         gguf_path: gguf.path,
         filename: gguf.filename,
         download_url: gguf.download_url,
         dim: gguf.dim,
         llama_server_path: server.path,
         download_precompiled: server.download_precompiled,
         download_engine_now: server.download_now,
         extra_args: extra_args,
         launcher_module: launcher.module,
         launcher_name: launcher.name,
         context_size: context_size,
         download_model?: download_model?
       }}
    end
  end

  defp ask_host do
    answer = Interactive.question("Host [#{@default_host}]:", color: :cyan)
    {:ok, if(answer == "", do: @default_host, else: answer)}
  end

  defp ask_port(target) do
    default = default_port(target)
    answer = Interactive.question("Port [#{default}]:", color: :cyan)

    case parse_port(answer, default) do
      {:ok, port} ->
        {:ok, port}

      :error ->
        Alaja.print_error("Port must be an integer between 1 and 65535")
        ask_port(target)
    end
  end

  defp ask_api_key do
    answer = Interactive.question("API key [#{@default_api_key}]:", color: :cyan)
    {:ok, if(answer == "", do: @default_api_key, else: answer)}
  end

  defp ask_gguf_dir do
    answer = Interactive.question("GGUF directory [#{@default_model_dir}]:", color: :cyan)
    path = if answer == "", do: @default_model_dir, else: answer
    {:ok, Path.expand(path)}
  end

  defp ask_gguf_file(target, dir) do
    existing = scan_ggufs(dir)

    options =
      Enum.map(existing, fn file ->
        {"#{file.filename} (local)", {:file, file.path}}
      end) ++
        [
          {"Custom path", :custom},
          {"Skip (configure later)", :skip}
        ]

    case Interactive.question_with_options("GGUF file", options, color: :cyan) do
      {:file, path} ->
        {:ok, gguf_info(target, path)}

      :custom ->
        ask_custom_gguf_path(target)

      :skip ->
        {:ok, %{path: nil, filename: nil, download_url: nil, dim: default_dim(target)}}

      :error ->
        Alaja.print_error("Choose a GGUF file, custom path, or skip")
        ask_gguf_file(target, dir)
    end
  end

  defp ask_custom_gguf_path(target) do
    answer = Interactive.question("GGUF file path:", color: :cyan)

    if answer == "" do
      {:ok, %{path: nil, filename: nil, download_url: nil, dim: default_dim(target)}}
    else
      {:ok, gguf_info(target, Path.expand(answer))}
    end
  end

  defp ask_llama_server_path do
    # First check if llama-server is available on PATH. If it is, offer
    # to use it directly. If not (or user declines), fall through to
    # the binary path / download options.
    case detect_llama_server_in_path() do
      {:ok, path} ->
        case Interactive.question_with_options(
               "llama-server path",
               [
                 {"Use llama-server in PATH (#{path})", :use_path},
                 {"Specify a different path", :existing},
                 {"Download precompiled now", :download_now}
               ],
               color: :cyan,
               default: 1
             ) do
          :use_path ->
            {:ok, %{path: path, download_precompiled: false, download_now: false}}

          :download_now ->
            {:ok, %{path: nil, download_precompiled: true, download_now: true}}

          :existing ->
            ask_existing_llama_server_path()

          :error ->
            Alaja.print_error("Choose how to find llama-server")
            ask_llama_server_path()
        end

      :not_found ->
        # llama-server not in PATH — only custom path or download.
        case Interactive.question_with_options(
               "llama-server path",
               [
                 {"Specify a path to an existing binary", :existing},
                 {"Download precompiled now", :download_now}
               ],
               color: :cyan,
               default: 1
             ) do
          :download_now ->
            {:ok, %{path: nil, download_precompiled: true, download_now: true}}

          :existing ->
            ask_existing_llama_server_path()

          :error ->
            Alaja.print_error("Choose how to find llama-server")
            ask_llama_server_path()
        end
    end
  end

  # Returns {:ok, path} if a working llama-server is in PATH, or
  # :not_found otherwise. We verify the binary actually runs (--version
  # exits 0) before recommending it — 'which' alone is not enough
  # because some PATH entries point to broken symlinks or scripts that
  # fail at runtime.
  defp detect_llama_server_in_path do
    with path when is_binary(path) <- System.find_executable("llama-server"),
         {output, 0} when is_binary(output) <-
           System.cmd(path, ["--version"], stderr_to_stdout: true) do
      # `output` looks like "version: 9985 (efb3036c1)\nbuilt with ..." for
      # a working llama-server. We don't parse it — just trust exit 0
      # and that *some* version banner was printed. (The previous
      # implementation pattern-matched `{:ok, _}` against the return
      # of `System.cmd/3` which actually returns `{output, exit_code}`,
      # so this function ALWAYS returned `:not_found`.)
      if String.contains?(output, "version") do
        {:ok, path}
      else
        :not_found
      end
    else
      _ -> :not_found
    end
  end

  defp ask_existing_llama_server_path do
    answer = Interactive.question("Path to llama-server binary:", color: :cyan)
    path = Path.expand(answer)

    cond do
      answer == "" ->
        Alaja.print_error("Path is required")
        ask_existing_llama_server_path()

      File.exists?(path) and not File.dir?(path) ->
        # Verify the binary actually runs before accepting it.
        case System.cmd(path, ["--version"], stderr_to_stdout: true) do
          {_out, 0} ->
            {:ok, %{path: path, download_precompiled: false, download_now: false}}

          {_out, code} ->
            Alaja.print_warning(
              "llama-server at #{path} exited with code #{code} when run with --version"
            )

            ask_existing_llama_server_path()
        end

      true ->
        Alaja.print_error("llama-server binary not found at #{path}")
        ask_existing_llama_server_path()
    end
  end

  defp ask_extra_args do
    answer = Interactive.question("Extra args (optional):", color: :cyan)

    {:ok, split_args(answer)}
  rescue
    ArgumentError ->
      Alaja.print_error("Could not parse extra args")
      ask_extra_args()
  end

  defp ask_launcher do
    answer = Interactive.question("Launcher custom module (optional):", color: :cyan)

    if answer == "" do
      {:ok, %{module: nil, name: nil}}
    else
      module = launcher_module(answer)

      if Code.ensure_loaded?(module) and function_exported?(module, :launch, 2) do
        {:ok, %{module: module, name: launcher_name(answer)}}
      else
        Alaja.print_warning("Launcher #{answer} is not loaded or does not export launch/2")
        ask_launcher()
      end
    end
  end

  defp ask_context_size(nil), do: {:ok, 4096}

  defp ask_context_size(path) do
    if File.exists?(path) do
      answer = Interactive.question("Context size [4096]:", color: :cyan)

      case parse_positive_integer(answer, 4096) do
        {:ok, size} ->
          {:ok, size}

        :error ->
          Alaja.print_error("Context size must be a positive integer")
          ask_context_size(path)
      end
    else
      {:ok, 4096}
    end
  end

  defp ask_download_model do
    {:ok, Interactive.yesno("Download model now?", default: :no) == :yes}
  end

  defp persist_and_register(:llm, answers) do
    sections = %{
      "llm" => config_section(:llm, answers),
      "summarize" => config_section(:summarize, answers)
    }

    LLM.merge_and_write(sections)
    :ok = register_with_candil(:llm, answers)
    :ok = maybe_download_engine(answers)
    :ok = maybe_download_model(answers)
    :ok
  end

  defp persist_and_register(target, answers) do
    section = config_section(target, answers)
    LLM.merge_and_write(%{section_name(target) => section})
    :ok = register_with_candil(target, answers)
    :ok = maybe_download_engine(answers)
    :ok = maybe_download_model(answers)
    :ok
  end

  defp config_section(:embedding, answers) do
    %{
      "provider" => "local",
      "url" => base_url(answers),
      "model" => model_name(:embedding, answers.gguf_path),
      "api_key" => answers.api_key,
      "dim" => answers.dim || 4096,
      "batch_size" => 32,
      "timeout_ms" => 30_000,
      "extra_args" => answers.extra_args,
      "gguf_path" => answers.gguf_path,
      "llama_server_path" => answers.llama_server_path,
      "download_precompiled" => answers.download_precompiled,
      "launcher" => answers.launcher_name
    }
  end

  defp config_section(:llm, answers) do
    %{
      "provider" => "local",
      "url" => base_url(answers),
      "model" => model_name(:llm, answers.gguf_path),
      "api_key" => answers.api_key,
      "timeout_ms" => 45_000,
      "explain_max_tokens" => 600,
      "query_max_tokens" => 512,
      "extra_args" => answers.extra_args,
      "gguf_path" => answers.gguf_path,
      "llama_server_path" => answers.llama_server_path,
      "download_precompiled" => answers.download_precompiled,
      "launcher" => answers.launcher_name
    }
  end

  defp config_section(:summarize, answers) do
    %{
      "provider" => "local",
      "url" => base_url(answers),
      "model" => model_name(:llm, answers.gguf_path),
      "api_key" => answers.api_key,
      "timeout_ms" => 45_000,
      "max_tokens" => 180,
      "extra_args" => answers.extra_args,
      "gguf_path" => answers.gguf_path,
      "llama_server_path" => answers.llama_server_path,
      "download_precompiled" => answers.download_precompiled,
      "launcher" => answers.launcher_name
    }
  end

  defp register_with_candil(target, answers) do
    _ = Application.ensure_all_started(:candil)

    engine = %Candil.Engine{
      alias: engine_alias(target),
      binary_dir: binary_dir_from_path(answers.llama_server_path),
      use_precompiled: answers.download_precompiled,
      host: answers.host,
      port: answers.port,
      start_args: answers.extra_args,
      launcher: answers.launcher_module
    }

    Candil.Config.register_engine(engine)

    if answers.gguf_path do
      model = %Candil.Model{
        alias: model_alias(target),
        type: :local,
        model_dir: Path.dirname(answers.gguf_path),
        filename: Path.basename(answers.gguf_path),
        download_url: answers.download_url,
        context_size: answers.context_size,
        engine: engine.alias,
        usage: usage(target)
      }

      Candil.Config.register_model(model)
    else
      Alaja.print_warning(
        "No GGUF configured for #{target_label(target)}; Candil model registration skipped"
      )
    end

    :ok
  end

  defp maybe_download_engine(%{download_engine_now: true}) do
    engine = Candil.Config.get_engine(:llm_engine) |> unwrap_registered()

    case engine || Candil.Config.get_engine(:embedding_engine) |> unwrap_registered() do
      nil ->
        :ok

      registered_engine ->
        case candil_module().download_engine(registered_engine) do
          :ok ->
            Alaja.print_success("llama-server downloaded")

          {:error, reason} ->
            Alaja.print_warning("Could not download llama-server: #{inspect(reason)}")

          _ ->
            :ok
        end
    end

    :ok
  end

  defp maybe_download_engine(_answers), do: :ok

  defp maybe_download_model(%{download_model?: true, gguf_path: path, download_url: url})
       when is_binary(path) and is_binary(url) do
    model = %Candil.Model{
      alias: :download_candidate,
      type: :local,
      model_dir: Path.dirname(path),
      filename: Path.basename(path),
      download_url: url,
      engine: :download_candidate_engine,
      usage: [:chat]
    }

    case candil_module().download_model(model) do
      {:ok, downloaded_path} -> Alaja.print_success("Model downloaded to #{downloaded_path}")
      {:error, reason} -> Alaja.print_warning("Could not download model: #{inspect(reason)}")
      _ -> :ok
    end

    :ok
  end

  defp maybe_download_model(%{download_model?: true}) do
    Alaja.print_warning("No HuggingFace download URL is known for this GGUF")
    :ok
  end

  defp maybe_download_model(_answers), do: :ok

  defp gguf_info(target, path) do
    filename = Path.basename(path)
    known = known_model(target, filename)

    %{
      path: path,
      filename: filename,
      download_url: if(File.exists?(path), do: nil, else: known && known.url),
      dim: known && Map.get(known, :dim, default_dim(target))
    }
  end

  defp known_model(target, filename) do
    target
    |> then(&Map.get(@known_models, &1, []))
    |> Enum.find(&(String.downcase(&1.filename) == String.downcase(filename)))
  end

  defp parse_port("", default), do: {:ok, default}

  defp parse_port(value, _default) do
    with {port, ""} <- Integer.parse(value),
         true <- port in 1..65_535 do
      {:ok, port}
    else
      _ -> :error
    end
  end

  defp parse_positive_integer("", default), do: {:ok, default}

  defp parse_positive_integer(value, _default) do
    with {integer, ""} <- Integer.parse(value),
         true <- integer > 0 do
      {:ok, integer}
    else
      _ -> :error
    end
  end

  defp split_args(""), do: []
  defp split_args(args), do: OptionParser.split(args)

  defp launcher_module(name) do
    name
    |> launcher_name()
    |> then(&String.to_atom("Elixir." <> &1))
  end

  defp launcher_name("Elixir." <> rest), do: rest
  defp launcher_name(name), do: String.trim(name)

  defp binary_dir_from_path(nil), do: nil

  defp binary_dir_from_path(path) do
    if Path.basename(path) == "llama-server" do
      Path.dirname(path)
    else
      path
    end
  end

  defp unwrap_registered({:ok, value}), do: value
  defp unwrap_registered({:error, :not_found}), do: nil
  defp unwrap_registered(value), do: value

  defp candil_module, do: Application.get_env(:delfos, :candil, Candil)

  defp base_url(answers), do: "http://#{answers.host}:#{answers.port}"
  defp default_port(:llm), do: 9999
  defp default_port(:embedding), do: 9998
  defp default_dim(:embedding), do: 4096
  defp default_dim(:llm), do: nil
  defp section_name(target), do: Atom.to_string(target)
  defp engine_alias(target), do: :"#{target}_engine"
  defp model_alias(target), do: :"#{target}_model"
  defp usage(:embedding), do: [:embeddings]
  defp usage(:llm), do: [:chat, :completion]

  defp model_name(target, nil), do: Atom.to_string(target)

  defp model_name(_target, path) do
    path
    |> Path.basename()
    |> String.replace(~r/\.gguf$/i, "")
  end

  defp target_label(:llm), do: "LLM"
  defp target_label(:embedding), do: "Embedding"

  defp skip_msg do
    Alaja.print_info("llama.cpp setup skipped")
    false
  end
end
