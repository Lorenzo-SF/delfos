defmodule Delfos.CLI.Commands.Setup.LLM.External do
  @moduledoc false

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive
  alias Delfos.CLI.Commands.Setup.LLM

  @default_base_url "https://api.openai.com/v1"

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

  defp configure(_target, :skip, _base_url, _api_key), do: skip_msg()

  defp configure(:both, provider, base_url, api_key) do
    sections =
      provider
      |> llm_section(base_url, api_key)
      |> Map.merge(embedding_section(base_url, api_key))

    persist_sections(provider, base_url, api_key, sections)
  end

  defp configure(:llm, provider, base_url, api_key) do
    persist_sections(provider, base_url, api_key, llm_section(provider, base_url, api_key))
  end

  defp configure(:embedding, _provider, base_url, api_key) do
    persist_sections(:openai, base_url, api_key, embedding_section(base_url, api_key))
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

  defp embedding_section(base_url, api_key) do
    model = ask_text("Embedding model [text-embedding-3-small]:", "text-embedding-3-small")
    dim = ask_integer("Embedding dimensions [1536]:", 1536)

    %{
      "embedding" => %{
        "provider" => "openai",
        "url" => api_base_without_v1(base_url),
        "model" => model,
        "api_key" => api_key,
        "dim" => dim,
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

    if embedding = sections["embedding"] do
      Candil.Config.register_model(%Candil.Model{
        alias: :embedding_model,
        type: :remote,
        name: embedding["model"],
        provider: provider_alias,
        usage: [:embeddings]
      })
    end

    if llm = sections["llm"] do
      Candil.Config.register_model(%Candil.Model{
        alias: :llm_model,
        type: :remote,
        name: llm["model"],
        provider: provider_alias,
        usage: [:chat, :completion]
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

  defp ask_integer(prompt, default) do
    case Interactive.question(prompt, color: :cyan) do
      "" ->
        default

      value ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 ->
            integer

          _ ->
            Alaja.print_error("Value must be a positive integer")
            ask_integer(prompt, default)
        end
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
