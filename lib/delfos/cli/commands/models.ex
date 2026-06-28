defmodule Delfos.CLI.Commands.Models do
  @moduledoc """
  Show the currently active models (embedding + LLM) and probe their endpoints.

  Useful to confirm what Delfos will use before running a query or
  summarisation. With `--probe` actually pings each endpoint and reports
  response time + first embedding/chat snippet.
  """

  alias Alaja
  alias Delfos.{Config.Manager, Repo}
  alias Delfos.LLM.Client

  @help """
  USAGE
      delfos models [flags]

  Show active models and (optionally) probe their endpoints.

  FLAGS
      --probe          Ping each endpoint and report latency

  EXAMPLES
      delfos models             # static config only
      delfos models --probe     # also check the endpoints respond
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [probe: :boolean])
    probe = opts[:probe] || false

    cfg_emb = Manager.embedding()
    cfg_llm = Manager.llm()

    Alaja.print_raw("\n=== ACTIVE MODELS ===\n\n")

    print_section("EMBEDDING", cfg_emb)
    print_section("LLM", cfg_llm)

    if cfg_llm[:use_thinker_for_query] && cfg_llm[:thinker_url] not in [nil, ""] do
      Alaja.print_raw("\nTHINKER (used for :query / :explain when configured)\n")

      Alaja.print_raw("  url   = #{cfg_llm[:thinker_url]}\n")
      Alaja.print_raw("  model = #{cfg_llm[:thinker_model]}\n")
    end

    if probe do
      Alaja.print_raw("\n--- Probing endpoints ---\n\n")
      probe_embedding(cfg_emb)
      probe_llm(cfg_llm)
    else
      Alaja.print_info("\nRun with --probe to ping the endpoints and report latency.")
    end

    Alaja.print_raw("\n")
    check_index_dim(cfg_emb[:dim])
  end

  defp print_section(title, cfg) do
    Alaja.print_raw(title <> "\n")
    Alaja.print_raw(String.duplicate("─", 40) <> "\n")
    Alaja.print_raw("  provider = #{cfg[:provider]}\n")
    Alaja.print_raw("  url      = #{cfg[:url]}\n")
    Alaja.print_raw("  model    = #{cfg[:model]}\n")
    Alaja.print_raw("  api_key  = #{mask(cfg[:api_key])}\n")
    Alaja.print_raw("  dim      = #{cfg[:dim]}\n")
  end

  defp probe_embedding(cfg_emb) do
    t0 = System.monotonic_time(:millisecond)

    case Client.embed("ping") do
      {:ok, vec} when is_list(vec) ->
        elapsed = System.monotonic_time(:millisecond) - t0

        Alaja.print_success("Embedding OK · dim=#{length(vec)} · #{elapsed}ms")

        if length(vec) != cfg_emb[:dim] do
          Alaja.print_warning(
            "dim mismatch — config says #{cfg_emb[:dim]}, server returned #{length(vec)}"
          )

          Alaja.print_info("Fix with: delfos config set embedding dim #{length(vec)}")
        end

      {:error, reason} ->
        Alaja.print_error("Embedding failed: #{format(reason)}")

        if cfg_emb[:provider] == :local do
          Alaja.print_info("Start with: llama-server --port 9998 --embedding -m <model>.gguf")
        end
    end

    Alaja.print_raw("\n")
  end

  defp probe_llm(cfg_llm) do
    t0 = System.monotonic_time(:millisecond)

    case Client.chat([%{role: "user", content: "ping"}], max_tokens: 5, use_case: :summarize) do
      {:ok, content} when is_binary(content) ->
        elapsed = System.monotonic_time(:millisecond) - t0

        Alaja.print_success(
          "LLM OK · #{elapsed}ms · response=#{inspect(String.slice(content, 0, 40))}"
        )

      {:error, reason} ->
        Alaja.print_error("LLM failed: #{format(reason)}")

        if cfg_llm[:provider] == :local do
          Alaja.print_info("Start with: llama-server --port 8080 -m <model>.gguf")
        end
    end

    Alaja.print_raw("\n")
  end

  defp check_index_dim(configured_dim) do
    # Read the actual column dimension from PostgreSQL for symbols.embedding
    Alaja.print_raw("INDEX DIMENSION CHECK\n")
    Alaja.print_raw(String.duplicate("─", 40) <> "\n")

    case Repo.query("SELECT atttypmod FROM pg_attribute
            WHERE attrelid = 'symbols'::regclass AND attname = 'embedding'") do
      {:ok, %{rows: [[nil]]}} ->
        Alaja.print_warning("No symbols table or no embedding column")

      {:ok, %{rows: [[dim]]}} ->
        if dim == configured_dim do
          Alaja.print_success("Symbols.embedding dim=#{dim} (matches config)")
        else
          Alaja.print_error("Symbols.embedding dim=#{dim} but config says #{configured_dim}")
          Alaja.print_info("Reset DB: mix ecto.drop && mix ecto.create && mix ecto.migrate")
        end

      {:error, reason} ->
        Alaja.print_warning("Cannot query symbols table: #{format(reason)}")
    end

    Alaja.print_raw("\n")
  end

  defp mask(nil), do: "(not set)"

  defp mask(key) when byte_size(key) <= 8 do
    String.duplicate("*", byte_size(key))
  end

  defp mask(key), do: String.slice(key, 0, 6) <> "..." <> String.slice(key, -4, 4)

  defp format(%Postgrex.Error{message: msg}) when is_binary(msg), do: msg
  defp format(reason), do: inspect(reason)
end
