defmodule Delfos.CLI.Commands.Setup.LLM.Ollama do
  @moduledoc false

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive
  alias Delfos.CLI.Commands.Setup.LLM
  alias Delfos.CLI.Commands.Setup.LLM.LlamaCpp

  @default_url "http://localhost:11434"

  @doc false
  def run(%{target: target}) when target in [:llm, :embedding, :both] do
    Alaja.print_raw("\n")
    Header.print("Ollama setup", subtitle: "Connect to a running Ollama daemon", size: :small)
    Alaja.print_raw("\n")

    url = ask_url()

    case probe_ollama(url) do
      {:ok, models} ->
        configure(target, url, models)

      {:error, reason} ->
        Alaja.print_warning("Ollama not reachable: #{reason}")
        handle_unreachable(target)
    end
  end

  defp ask_url do
    answer = Interactive.question("Ollama URL [#{@default_url}]:", color: :cyan)
    if answer == "", do: @default_url, else: String.trim_trailing(answer, "/")
  end

  defp configure(:both, url, models) do
    with {:ok, embedding} <- pick_model(models, "Embedding model"),
         {:ok, llm} <- pick_model(models, "LLM model") do
      dim = detect_ollama_dim(url, embedding)

      persist_sections(%{
        "embedding" => embedding_config(url, embedding, dim),
        "llm" => llm_config(url, llm),
        "summarize" => summarize_config(url, llm)
      })
    else
      :skip -> skip_msg()
    end
  end

  defp configure(:embedding, url, models) do
    with {:ok, embedding} <- pick_model(models, "Embedding model") do
      persist_sections(%{
        "embedding" => embedding_config(url, embedding, detect_ollama_dim(url, embedding))
      })
    else
      :skip -> skip_msg()
    end
  end

  defp configure(:llm, url, models) do
    with {:ok, llm} <- pick_model(models, "LLM model") do
      persist_sections(%{
        "llm" => llm_config(url, llm),
        "summarize" => summarize_config(url, llm)
      })
    else
      :skip -> skip_msg()
    end
  end

  defp persist_sections(sections) do
    LLM.merge_and_write(sections)
    register_with_candil(sections)
    Alaja.print_success("Ollama configuration saved")
    true
  end

  defp probe_ollama(url) do
    case Apero.Http.get("#{url}/api/tags", [], receive_timeout: 5_000) do
      {:ok, %{status: status, body: %{"models" => models}}} when status in 200..299 ->
        {:ok, Enum.map(models, fn model -> model["name"] end)}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, _reason} ->
        {:error, "connection refused — is Ollama running?"}
    end
  end

  defp handle_unreachable(target) do
    case Interactive.question_with_options(
           "What do you want to do?",
           [
             {"Install Ollama manually", :install},
             {"Try llama.cpp instead", :llama_cpp},
             {"Skip", :skip}
           ],
           color: :cyan,
           default: 2
         ) do
      :install ->
        Alaja.print_info("Install Ollama from https://ollama.com/download, then rerun setup.")
        false

      :llama_cpp ->
        LlamaCpp.run(%{target: target})

      :skip ->
        skip_msg()

      :error ->
        skip_msg()
    end
  end

  defp pick_model([], label) do
    answer = Interactive.question("#{label} name (ollama pull <name>):", color: :cyan)

    if answer == "" do
      :skip
    else
      {:ok, answer}
    end
  end

  defp pick_model(models, label) do
    Header.print(label, subtitle: "Available in Ollama", size: :small)

    options =
      models
      |> Enum.sort()
      |> Enum.map(fn model -> {model, model} end)
      |> Kernel.++([{"Custom model name", :custom}, {"Skip", :skip}])

    case Interactive.question_with_options("Which model?", options, color: :cyan) do
      :custom ->
        pick_model([], label)

      :skip ->
        :skip

      :error ->
        Alaja.print_error("Choose a model or skip")
        pick_model(models, label)

      model when is_binary(model) ->
        {:ok, model}
    end
  end

  defp detect_ollama_dim(url, model) do
    case Apero.Http.post("#{url}/api/embed", %{model: model, input: "test"}, [],
           receive_timeout: 10_000
         ) do
      {:ok, %{body: %{"embeddings" => [vec | _]}}} when is_list(vec) -> length(vec)
      _ -> 1536
    end
  end

  defp embedding_config(url, model, dim) do
    %{
      "provider" => "ollama",
      "url" => url,
      "model" => model,
      "api_key" => "sk-local-dev-key",
      "dim" => dim,
      "batch_size" => 32,
      "timeout_ms" => 30_000
    }
  end

  defp llm_config(url, model) do
    %{
      "provider" => "ollama",
      "url" => url,
      "model" => model,
      "api_key" => "sk-local-dev-key",
      "timeout_ms" => 45_000,
      "explain_max_tokens" => 600,
      "query_max_tokens" => 512
    }
  end

  defp summarize_config(url, model) do
    %{
      "provider" => "ollama",
      "url" => url,
      "model" => model,
      "api_key" => "sk-local-dev-key",
      "timeout_ms" => 45_000,
      "max_tokens" => 180
    }
  end

  defp register_with_candil(sections) do
    _ = Application.ensure_all_started(:candil)

    provider = %Candil.Provider{
      alias: :delfos_ollama,
      type: :ollama,
      base_url: ollama_base_url(sections)
    }

    Candil.Config.register_provider(provider)

    if embedding = sections["embedding"] do
      Candil.Config.register_model(%Candil.Model{
        alias: :embedding_model,
        type: :remote,
        name: embedding["model"],
        provider: provider.alias,
        usage: [:embeddings]
      })
    end

    if llm = sections["llm"] do
      Candil.Config.register_model(%Candil.Model{
        alias: :llm_model,
        type: :remote,
        name: llm["model"],
        provider: provider.alias,
        usage: [:chat, :completion]
      })
    end

    :ok
  rescue
    e ->
      Alaja.print_warning("Could not register Ollama in Candil: #{Exception.message(e)}")
      :ok
  end

  defp ollama_base_url(%{"embedding" => %{"url" => url}}), do: url
  defp ollama_base_url(%{"llm" => %{"url" => url}}), do: url

  defp skip_msg do
    Alaja.print_info("Ollama setup skipped")
    false
  end
end
