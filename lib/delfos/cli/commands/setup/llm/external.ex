defmodule Delfos.CLI.Commands.Setup.LLM.External do
  @moduledoc false

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive
  alias Delfos.CLI.Commands.Setup.LLM

  @doc false
  def run(%{target: target}) when target in [:llm, :embedding, :both] do
    Alaja.print_raw("\n")
    Header.print("Endpoint setup", subtitle: "OpenAI-friendly or Anthropic-friendly API", size: :small)
    Alaja.print_raw("\n")

    ip = ask_ip()
    port = ask_port()
    api_key = ask_api_key()
    type = detect_or_ask_type(ip, port, api_key)
    configure(target, type, ip, port, api_key)
  end

  defp ask_ip do
    answer = Interactive.question("Host/IP [127.0.0.1]:", color: :cyan)
    if answer == "", do: "127.0.0.1", else: answer
  end

  defp ask_port do
    answer = Interactive.question("Port [9999]:", color: :cyan)

    case Integer.parse(if answer == "", do: "9999", else: answer) do
      {integer, ""} when integer > 0 and integer <= 65_535 -> integer
      _ ->
        Alaja.print_error("Port must be a number between 1 and 65535")
        ask_port()
    end
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

  defp detect_or_ask_type(ip, port, api_key) do
    Alaja.print_info("Probing API to detect protocol type...")

    case probe_type(ip, port, api_key) do
      :openai ->
        Alaja.print_success("Detected: OpenAI-compatible API")
        "openai"

      :anthropic ->
        Alaja.print_success("Detected: Anthropic-compatible API")
        "anthropic"

      {:error, reason} ->
        Alaja.print_warning("Could not detect protocol type: #{reason}")

        case Interactive.question_with_options(
               "Which API type is this?",
               [
                 {"OpenAI-friendly", "openai"},
                 {"Anthropic-friendly", "anthropic"},
                 {"Skip", :skip}
               ],
               color: :cyan,
               default: 1
             ) do
          type when type in ["openai", "anthropic"] -> type
          _ -> :skip
        end
    end
  end

  defp configure(_target, :skip, _ip, _port, _api_key), do: skip_msg()

  defp configure(target, type, ip, port, api_key) do
    sections =
      case target do
        :both -> Map.merge(llm_sections(type, ip, port, api_key), embedding_section(ip, port, api_key))
        :llm -> llm_sections(type, ip, port, api_key)
        :embedding -> embedding_section(ip, port, api_key)
      end

    LLM.merge_and_write(sections)
    Alaja.print_success("Endpoint configuration saved")
    true
  end

  defp llm_sections("anthropic", ip, port, api_key) do
    model = ask_text("Chat model [claude-sonnet-4-20250514]:", "claude-sonnet-4-20250514")

    %{
      "llm" => %{
        "ip" => ip,
        "port" => port,
        "type" => "anthropic",
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512
      },
      "summarize" => %{
        "ip" => ip,
        "port" => port,
        "type" => "anthropic",
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "max_tokens" => 180
      }
    }
  end

  defp llm_sections(_type, ip, port, api_key) do
    model = ask_text("Chat model [gpt-oss]:", "gpt-oss")

    %{
      "llm" => %{
        "ip" => ip,
        "port" => port,
        "type" => "openai",
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "explain_max_tokens" => 600,
        "query_max_tokens" => 512
      },
      "summarize" => %{
        "ip" => ip,
        "port" => port,
        "type" => "openai",
        "model" => model,
        "api_key" => api_key,
        "timeout_ms" => 45_000,
        "max_tokens" => 180
      }
    }
  end

  defp embedding_section(ip, port, api_key) do
    model = ask_text("Embedding model [jina-code-embeddings]:", "jina-code-embeddings")

    %{
      "embedding" => %{
        "ip" => ip,
        "port" => port,
        "model" => model,
        "api_key" => api_key,
        "batch_size" => 32,
        "timeout_ms" => 30_000
      }
    }
  end

  defp probe_type(ip, port, api_key) do
    base = "http://#{ip}:#{port}"

    case Apero.Http.post(
           "#{base}/v1/embeddings",
           %{model: "text-embedding-3-small", input: "ping"},
           [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :openai

      {:ok, %{status: 404}} ->
        probe_anthropic(base, api_key)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  defp probe_anthropic(base, api_key) do
    case Apero.Http.post(
           "#{base}/v1/messages",
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

      {:error, reason} ->
        {:error, "Anthropic probe failed: #{inspect(reason)}"}
    end
  end

  defp ask_text(prompt, default) do
    case Interactive.question(prompt, color: :cyan) do
      "" -> default
      value -> value
    end
  end

  defp skip_msg do
    Alaja.print_info("Endpoint setup skipped")
    false
  end
end
