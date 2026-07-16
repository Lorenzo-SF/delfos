defmodule Delfos.CLI.LLMGuard do
  @moduledoc """
  Pre-flight check that verifies LLM availability for a given command
  before the command runs.

  Two check levels are enforced:

    * `:required` — the command cannot work without a reachable LLM.
      On failure, prints an error explaining what's missing and how to
      fix it, then halts with exit code 78 (`EX_CONFIG`).

    * `:optional` — the command can produce degraded output without a
      reachable LLM. On failure, prints a warning explaining what's
      degraded, but lets the command continue.

  See `docs/LLM_USAGE.md` for the full per-command matrix.

  The check uses `Candil.Health.probe/2` so it verifies the HTTP health/model
  endpoint instead of only checking that a TCP port is open.
  """

  alias Alaja
  alias Delfos.Config.Manager

  # Per-command LLM requirements.
  #
  #   :required | :optional | :none
  #   embed: does this command need the embedding endpoint?
  #   chat:   does this command need the chat endpoint?
  #   reason: human-readable explanation shown when missing
  @requirements %{
    # ── MUST have working LLM (5) ──────────────────────────────────────────
    "scan" => %{
      need: :required,
      embed: true,
      chat: false,
      reason: "scan embeds every symbol"
    },
    "query" => %{
      need: :required,
      embed: true,
      chat: false,
      reason: "query uses vector search (needs embeddings)"
    },
    "explain" => %{
      need: :required,
      embed: true,
      chat: true,
      reason: "explain uses embeddings + chat"
    },
    "summarize" => %{
      need: :required,
      embed: true,
      chat: true,
      reason: "summarize embeds + chats per symbol"
    },
    "mcp" => %{
      need: :required,
      embed: true,
      chat: true,
      reason: "MCP server exposes tools that use both endpoints"
    },
    "init" => %{
      need: :required,
      embed: true,
      chat: false,
      reason: "init triggers a full scan (needs embeddings)"
    },
    # ── SHOULD have LLM, degrades if missing (1) ───────────────────────────
    # `delfos mcp` requires both endpoints (chat + embed) since all the
    # MCP tools may use either depending on the request. Migrated from
    # the legacy `delfos watch` entry (removed in v2.3.0 — the watcher
    # is now part of the MCP server's supervision tree).
    "watch" => %{
      need: :optional,
      # `watch` (now part of the MCP server's supervision tree) uses
      # embeddings to detect semantic change events — so we DO want to
      # probe the embedding endpoint, but only warn (not halt) when
      # it's down.
      embed: true,
      chat: false,
      reason: "watch uses embeddings for change detection"
    },
    # ── No LLM needed (7) ──────────────────────────────────────────────────
    "audit" => %{need: :none},
    "graph" => %{need: :none},
    "config" => %{need: :none},
    "status" => %{need: :none},
    "integrate" => %{need: :none},
    "doctor" => %{need: :none},
    "version" => %{need: :none},
    "help" => %{need: :none}
  }

  @typedoc """
  Outcome of `check/1`.
    - `:ok` — LLM is available or not needed, command can proceed
    - `:warn` — LLM is missing but command can continue with degraded
      quality. Caller should print the warning and proceed.
    - `{:halt, :required}` — required LLM is missing. Caller should
      print the error and exit.
  """
  @type outcome :: :ok | :warn | {:halt, :required}

  @doc """
  Checks LLM availability for `command` (a top-level delfos command name).

  Returns one of:
    * `:ok`              — LLM is reachable or not needed
    * `:warn`            — LLM is missing but the command can proceed with
                          degraded results. The warning has already been
                          printed via Alaja.
    * `{:halt, :required}` — required LLM is missing. The error has
                          already been printed. Caller should
                          `System.halt(78)`.
  """
  @spec check(String.t()) :: outcome()
  def check(command) when is_binary(command) do
    case Map.get(@requirements, command) do
      nil ->
        :ok

      %{need: :none} ->
        :ok

      %{need: :required, embed: needs_embed, chat: needs_chat, reason: reason} ->
        check_required(needs_embed, needs_chat, reason)

      %{need: :optional, embed: needs_embed, chat: needs_chat, reason: reason} ->
        check_optional(needs_embed, needs_chat, reason)
    end
  end

  @doc """
  Returns the requirement level for a command (`:required`, `:optional`,
  `:none`, or `nil` if unknown).
  """
  @spec requirement(String.t()) :: :required | :optional | :none | nil
  def requirement(command) do
    case Map.get(@requirements, command) do
      nil -> nil
      %{need: level} -> level
    end
  end

  # ── Private ────────────────────────────────────────────────────────────

  defp check_required(needs_embed, needs_chat, reason) do
    embed_status = probe(embedding_url(), needs_embed)
    chat_status = probe(chat_url(), needs_chat)

    case {normalize(embed_status), normalize(chat_status)} do
      {:ok, :ok} ->
        :ok

      _ ->
        print_required_failure(reason, embed_status, chat_status)
        {:halt, :required}
    end
  end

  defp check_optional(needs_embed, needs_chat, reason) do
    embed_status = probe(embedding_url(), needs_embed)
    chat_status = probe(chat_url(), needs_chat)

    case {normalize(embed_status), normalize(chat_status)} do
      {:ok, :ok} ->
        :ok

      _ ->
        print_optional_failure(reason, embed_status, chat_status)
        :warn
    end
  end

  # Treat :skip the same as :ok for the "did all required endpoints
  # check out?" decision. Skipped endpoints are still printed so the
  # user knows what was probed.
  defp normalize(:skip), do: :ok
  defp normalize(other), do: other

  defp probe(_url, false), do: :skip

  defp probe(url, true) do
    case url do
      nil ->
        {:missing, "no URL configured for this endpoint"}

      url ->
        case health_module().probe(url, timeout: 500) do
          %{reachable: true} -> :ok
          _ -> {:unreachable, url}
        end
    end
  end

  defp embedding_url do
    Manager.embedding()[:url]
  end

  defp chat_url do
    Manager.llm()[:url]
  end

  defp health_module, do: Application.get_env(:delfos, :candil_health, Candil.Health)

  # ── Output ──────────────────────────────────────────────────────────────

  defp print_required_failure(reason, embed_status, chat_status) do
    Alaja.print_error("Command requires a working LLM, but:")
    Alaja.print_raw("  Reason: #{reason}\n\n")
    print_endpoint_status("Embedding", embedding_url(), embed_status)
    print_endpoint_status("Chat", chat_url(), chat_status)

    Alaja.print_raw("\n")
    Alaja.print_info("How to fix:")
    Alaja.print_raw("  1. Register the endpoints: scripts/register-local-llms.sh\n")
    Alaja.print_raw("  2. Start the servers:\n")
    Alaja.print_raw("       llama-run embed                # in one terminal\n")
    Alaja.print_raw("       llama-run gpt_oss medium      # in another terminal\n")
    Alaja.print_raw("  3. Re-run with --fix: delfos doctor --fix\n")
  end

  defp print_optional_failure(reason, embed_status, chat_status) do
    Alaja.print_warning("LLM partially unavailable — running with degraded quality")
    Alaja.print_raw("  Reason: #{reason}\n\n")
    print_endpoint_status("Embedding", embedding_url(), embed_status)
    print_endpoint_status("Chat", chat_url(), chat_status)

    Alaja.print_raw("\n")
    Alaja.print_info("Some features will be missing or lower quality.")
    Alaja.print_raw("  Start the servers to get full results:\n")
    Alaja.print_raw("    llama-run embed & llama-run gpt_oss medium &\n")
  end

  defp print_endpoint_status(label, url, status) do
    Alaja.print_raw("  #{String.pad_trailing(label <> ":", 12)}")

    case status do
      :skip ->
        Alaja.print_raw("(not needed for this command)\n")

      :ok ->
        Alaja.print_success("reachable at #{url}")

      {:missing, reason} ->
        Alaja.print_raw("#{reason}\n")

      {:unreachable, _url} ->
        Alaja.print_raw("✗ unreachable at #{url}\n")
    end
  end
end
