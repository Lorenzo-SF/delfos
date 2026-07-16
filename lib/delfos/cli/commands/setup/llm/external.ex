defmodule Delfos.CLI.Commands.Setup.LLM.External do
  @moduledoc false

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive
  alias Delfos.CLI.Commands.Setup.LLM

  @default_base_url "https://api.openai.com/v1"
  @compile_embed_model Application.compile_env(:delfos, :embedding, [])[:model] ||
                         "text-embedding-3-small"

  @doc false
  def run(%{target: target}) when target in [:llm, :embedding, :both] do
    Alaja.print_raw("\n")
    Header.print("External API setup", subtitle: "OpenAI, Anthropic, or compatible", size: :small)
    Alaja.print_raw("\n")

    base_url = ask_base_url()
    api_key = ask_api_key()

    provider = detect_or_ask_provider(base_url, api_key)
    configure(target, provider, base_url, api_key)
  end

  defp ask_base_url do
    answer = Interactive.question("Base URL [#{@default_base_url}]:", color: :cyan)

    answer
    |> then(fn value -> if value == "", do: @default_base_url, else: value end)
    |> String.trim_trailing("/")
  end

  defp ask_api_key do
    case Interactive.question("API key:", color: :cyan) do
      "" ->
        Alaja.print_error("API key is required")
        ask_api_key()

      api_key ->
        api_key
    end
  end

  defp detect_or_ask_provider(base_url, api_key) do
    Alaja.print_info("Probing API to detect provider type...")

    case probe_provider(base_url, api_key) do
      :openai ->
        Alaja.print_success("Detected: OpenAI-compatible API")
        :openai

      :anthropic ->
        Alaja.print_success("Detected: Anthropic-compatible API")
        :anthropic

      {:error, reason} ->
        Alaja.print_warning("Could not detect provider type: #{reason}")

        case Interactive.question_with_options(
               "Which provider type is this?",
               [
                 {"OpenAI-compatible", :openai},
                 {"Anthropic-compatible", :anthropic},
                 {"Skip", :skip}
               ],
               color: :cyan,
               default: 1
             ) do
          provider when provider in [:openai, :anthropic] -> provider
          _ -> :skip
        end
    end
  end

  def configure(_target, :skip, _base_url, _api_key), do: skip_msg()

  def configure(:both, provider, base_url, api_key) do
    base = llm_section(provider, base_url, api_key)

    sections =
      case provider do
        :anthropic ->
          # Anthropic has no embeddings endpoint. Skip the embedding section
          # entirely — user must run setup again with target :embedding using
          # an OpenAI-compatible provider if they want remote embeddings.
          Alaja.print_warning(
            "Anthropic does not provide an embeddings endpoint. " <>
              "Skipping the 'embedding' section — re-run with target :embedding " <>
              "using an OpenAI-compatible provider if you need remote embeddings. " <>
              "Otherwise embeddings will come from the local llama-server " <>
              "(compile-time config in config/config.exs)."
          )

          base

        _ ->
          Map.merge(base, embedding_section(provider, base_url, api_key))
      end

    persist_sections(provider, base_url, api_key, sections)
  end

  def configure(:llm, provider, base_url, api_key) do
    persist_sections(provider, base_url, api_key, llm_section(provider, base_url, api_key))
  end

  def configure(:embedding, _provider, _base_url, _api_key) do
    # Embedding model/dim are compile-time fixed — the wizard cannot edit them.
    # External API setup doesn't write the embedding section at all (since
    # `embedding.model`/`embedding.dim`/`embedding.pooling` are read from
    # `config/config.exs` at compile time via `Application.compile_env/3`).
    Alaja.print_warning(
      "Embedding model and dim are compile-time fixed in config/config.exs. " <>
        "The external API wizard does not edit them — they apply to the local " <>
        "llama-server regardless of provider. To change them, edit " <>
        "config/config.exs and recompile delfos."
    )

    false
  end

  defp probe_provider(base_url, api_key) do
    case Apero.Http.post(
           api_url(base_url, "/embeddings"),
           %{model: "text-embedding-3-small", input: "ping"},
           [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :openai

      {:ok, %{status: 404}} ->
        probe_anthropic(base_url, api_key)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %Apero.Http.Error{reason: reason}} ->
        {:error, "Connection failed: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  defp probe_anthropic(base_url, api_key) do
    case Apero.Http.post(
           api_url(base_url, "/messages"),
           %{
             model: "claude-sonnet-4-20250514",
             max_tokens: 1,
             messages: [%{role: "user", content: "hi"}]
           },
           [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
           receive_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :anthropic

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status} — not OpenAI or Anthropic"}

      {:error, %Apero.Http.Error{reason: reason}} ->
        {:error, "Anthropic probe failed: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Anthropic probe failed: #{inspect(reason)}"}
    end
  end

  defp llm_section(:anthropic, base_url, api_key) do
    model = ask_text("Chat model [claude-sonnet-4-20250514]:", "claude-sonnet-4-20250514")

    %{
      "llm" => %{
        "provider" => "anthropic",
        "url" => api_base_without_v1(base_url),
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512
      },
      "summarize" => %{
        "provider" => "anthropic",
        "url" => api_base_without_v1(base_url),
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "max_tokens" => 180
      }
    }
  end

  defp llm_section(_provider, base_url, api_key) do
    model = ask_text("Chat model [gpt-4o]:", "gpt-4o")

    %{
      "llm" => %{
        "provider" => "openai",
        "url" => api_base_without_v1(base_url),
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512
      },
      "summarize" => %{
        "provider" => "openai",
        "url" => api_base_without_v1(base_url),
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "max_tokens" => 180
      }
    }
  end

  def embedding_section(provider, base_url, api_key) do
    # Embedding model/dim are compile-time fixed in config/config.exs
    # so we don't prompt for them here. We only return runtime-editable keys.
    # The actual values are read from Application.compile_env/3 at module load time.

    # Determine the correct provider type for embedding section
    embedding_provider =
      case provider do
        # Anthropic uses OpenAI-compatible embeddings
        :anthropic -> "openai"
        _ -> "openai"
      end

    %{
      "embedding" => %{
        "provider" => embedding_provider,
        "url" => api_base_without_v1(base_url),
        "api_key" => api_key,
        "batch_size" => 32,
        "timeout_ms" => 30_000
      }
    }
  end

  defp persist_sections(provider, base_url, api_key, sections) do
    LLM.merge_and_write(sections)
    register_provider(provider, base_url, api_key, sections)
    Alaja.print_success("External API configuration saved")
    true
  end

  defp register_provider(provider, base_url, _api_key, sections) do
    _ = Application.ensure_all_started(:candil)

    provider_alias = provider_alias(provider)

    Candil.Config.register_provider(%Candil.Provider{
      alias: provider_alias,
      type: provider_type(provider),
      base_url: api_base_without_v1(base_url)
    })

    # Register Candil's chat/completion model with the user-picked name.
    if llm = sections["llm"] do
      Candil.Config.register_model(%Candil.Model{
        alias: :llm_model,
        type: :remote,
        name: llm["model"],
        provider: provider_alias,
        usage: [:chat, :completion]
      })
    end

    # Embedding model name is compile-time (read from config/config.exs),
    # so we register it with the same name Candil uses for local embeddings.
    if sections["embedding"] do
      Candil.Config.register_model(%Candil.Model{
        alias: :embedding_model,
        type: :remote,
        name: @compile_embed_model,
        provider: provider_alias,
        usage: [:embeddings]
      })
    end

    :ok
  rescue
    e ->
      Alaja.print_warning(
        "Could not register external provider in Candil: #{Exception.message(e)}"
      )

      :ok
  end

  defp ask_text(prompt, default) do
    case Interactive.question(prompt, color: :cyan) do
      "" -> default
      value -> value
    end
  end

  defp api_url(base_url, path) do
    base = String.trim_trailing(base_url, "/")

    cond do
      String.ends_with?(base, "/v1") -> base <> path
      true -> base <> "/v1" <> path
    end
  end

  defp api_base_without_v1(base_url) do
    base_url
    |> String.trim_trailing("/")
    |> String.replace_suffix("/v1", "")
  end

  defp provider_alias(:anthropic), do: :delfos_anthropic
  defp provider_alias(_provider), do: :delfos_openai
  defp provider_type(:anthropic), do: :anthropic
  defp provider_type(_provider), do: :openai

  defp skip_msg do
    Alaja.print_info("External API setup skipped")
    false
  end
end
