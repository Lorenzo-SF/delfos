defmodule Delfos.CLI.Commands.Config do
  @moduledoc """
  Single entry point for managing Delfos configuration, models, and setup.

  This command unifies what used to be three separate commands
  (`config`, `models`, `setup`) into one. Run `delfos config` with no
  args to see the full list of subcommands.

  File: `~/.config/delfos/config.json`

  See `help_text/0` for the subcommand list.
  """

  @help """
  USAGE
      delfos config <subcommand>

  SUBCOMMANDS
      show                         Show active configuration
      path                         Print the config file path
      init                         Create the config file with defaults
      get <section> <key>          Read a value
      set <section> <key> <value>  Write a value
      preset <name>                Apply a provider preset (local|anthropic|openai|openai-large)
      setup [db|llm]               Interactive setup wizard (DB / LLM)
      models [--probe]             Show active embedding/LLM models

  Sections: embedding | llm | analysis | indexing | database

  Presets: local | anthropic | openai | openai-large

  EXAMPLES
      delfos config show
      delfos config preset local
      delfos config set llm provider anthropic
      delfos config set llm api_key sk-ant-xxxxx
      delfos config set embedding api_key sk-xxxxx
      delfos config get llm model
      delfos config models              # show active models
      delfos config setup db           # DB setup wizard
      delfos config setup llm          # LLM setup wizard
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  alias Alaja
  alias Delfos.Config.Manager

  # Presets of the most-used providers.
  #
  # IMPORTANT: `embedding.model` and `embedding.dim` are NOT included
  # below — they're compile-time fixed in `config/config.exs` and read
  # via `Application.get_env(:delfos, :embedding)`. The runtime
  # embed server URL and auth still come from presets (and can be
  # overwritten with `delfos config set`).
  @presets %{
    "local" => [
      {"embedding", "provider", "local"},
      {"embedding", "url", "http://127.0.0.1:9998"},
      {"embedding", "api_key", "sk-local-dev-key"},
      {"llm", "provider", "local"},
      {"llm", "url", "http://127.0.0.1:9999"},
      {"llm", "api_key", "sk-local-dev-key"}
    ],
    "anthropic" => [
      {"llm", "provider", "anthropic"},
      {"llm", "url", "https://api.anthropic.com"},
      {"llm", "model", "claude-sonnet-4-20250514"}
    ],
    "openai" => [
      {"embedding", "provider", "openai"},
      {"embedding", "url", "https://api.openai.com"},
      {"llm", "provider", "openai"},
      {"llm", "url", "https://api.openai.com"},
      {"llm", "model", "gpt-4o-mini"}
    ],
    "openai-large" => [
      {"embedding", "provider", "openai"},
      {"embedding", "url", "https://api.openai.com"},
      {"llm", "provider", "openai"},
      {"llm", "url", "https://api.openai.com"},
      {"llm", "model", "gpt-4o"}
    ]
  }

  # Compile-time fixed keys. Setting them at runtime would silently
  # break invariants:
  #   - embedding.{dim,model,pooling}: the pgvector column type matches
  #     these at boot — see `Delfos.DBMigrator`.
  #   - llm.model: the GGUF filename loaded by `llama-run gpt-oss`
  #     (via `LLAMA_LLM_MODEL` env var). Changing it without recompiling
  #     delfos would leave the wrapper script out of sync with delfos.
  # To change them, edit `config/config.exs` and recompile.
  @compile_time_fixed_keys ~w(dim model pooling)
  @compile_time_fixed_llm_keys ~w(model)

  # Returns true when (section, key) is compile-time fixed.
  defp compile_time_key?("embedding", key), do: key in @compile_time_fixed_keys
  defp compile_time_key?("llm", key), do: key in @compile_time_fixed_llm_keys
  defp compile_time_key?(_, _), do: false

  def run(["show" | _]) do
    Alaja.print_raw(Manager.show())
  end

  def run(["path" | _]) do
    Alaja.print_raw(Manager.config_file() <> "\n")
  end

  def run(["init" | _]) do
    path = Manager.config_file()

    if File.exists?(path) do
      Alaja.print_warning("Already exists: #{path}")
      Alaja.print_info("Run 'delfos config show' to see the active configuration.")
    else
      # Force-create the JSON config file with sensible defaults.
      # We delegate to Manager.default_config_content/0 so the file
      # we write matches exactly what Manager.load/0 expects.
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Manager.default_config_content())
      Alaja.print_success("Created: #{path}")
    end
  end

  def run(["get", section, key | _]) do
    cfg = Manager.load()

    case get_in(cfg, [section, key]) do
      nil ->
        Alaja.print_warning("(not found: [#{section}] #{key})")

      value ->
        Alaja.print_raw(inspect(value) <> "\n")
    end
  end

  @valid_sections ~w(models embedding llm summarize analysis indexing database)

  # Runtime-editable keys per section. Note: `embedding.model`,
  # `embedding.dim`, `embedding.pooling`, and `llm.model` are NOT here
  # because they are compile-time fixed in `config/config.exs`
  # (see `compile_time_key?/2` and the block at the top of this module).
  @valid_keys %{
    "models" => ~w(gguf_dir),
    "embedding" => ~w(provider url api_key batch_size timeout_ms
                      ctx_size n_gpu_layers slot_dir),
    "llm" => ~w(provider url api_key timeout_ms explain_max_tokens
                query_max_tokens),
    "summarize" => ~w(provider url model api_key timeout_ms max_tokens),
    "analysis" => ~w(churn_max_commits),
    "indexing" => ~w(ignore_dirs max_chunk_tokens),
    "database" => ~w(hostname port username password database)
  }

  def run(["set", section, key, value | _]) do
    cond do
      section not in @valid_sections ->
        Alaja.print_error("Unknown section: '#{section}'")
        Alaja.print_info("Valid sections: #{Enum.join(@valid_sections, ", ")}")
        # Bug #5 fix: exit 1 para que scripts detecten config inválido.
        # v2.6.0: raise Delfos.CLI.Abort instead of System.halt so the
        # CLI dispatcher can convert to exit(1) at the top level. Tests
        # can rescue the exception instead of being killed.
        raise Delfos.CLI.Abort, message: "unknown section: #{section}", code: 1

      compile_time_key?(section, key) ->
        reason =
          case {section, key} do
            {"embedding", k} when k in ~w(dim model pooling) ->
              "'#{k}' is part of the embed model contract. " <>
                "The pgvector column type and the LLama server config both " <>
                "must match this value, and changing them mid-flight would " <>
                "invalidate existing embeddings."

            {"llm", "model"} ->
              "'llm.model' is the GGUF filename loaded by `llama-run gpt-oss` " <>
                "(via `LLAMA_LLM_MODEL` env var). Changing it without " <>
                "recompiling delfos would leave the wrapper script out of sync."

            _ ->
              "'#{section}.#{key}' is compile-time fixed."
          end

        Alaja.print_error(
          "'#{section}.#{key}' is compile-time fixed in config/config.exs. " <>
            "Changing it requires editing that file and recompiling delfos."
        )

        Alaja.print_info("Reason: #{reason}")

        raise Delfos.CLI.Abort, message: "compile-time fixed key: #{section}.#{key}", code: 1

      key not in Map.get(@valid_keys, section, []) ->
        valid = Map.get(@valid_keys, section, [])
        Alaja.print_error("Unknown key: '#{section}.#{key}'")
        Alaja.print_info("Valid keys for '#{section}': #{Enum.join(valid, ", ")}")
        raise Delfos.CLI.Abort, message: "unknown key: #{section}.#{key}", code: 1

      true ->
        case Manager.set(section, key, value) do
          :ok ->
            Alaja.print_success("[#{section}] #{key} = #{value}")
            # Warn if embedding provider changed and dim might be misaligned
            if section == "embedding" and key == "provider" do
              suggest_dim_for_provider(value)
            end

          _ ->
            :noop
        end
    end
  end

  def run(["preset", name | _]) do
    case Map.get(@presets, name) do
      nil ->
        Alaja.print_error("Unknown preset: #{name}")
        Alaja.print_info("Available presets: #{Map.keys(@presets) |> Enum.join(", ")}")
        # Bug #5 fix: raise Delfos.CLI.Abort (v2.6.0) so tests can rescue.
        raise Delfos.CLI.Abort, message: "unknown preset: #{name}", code: 1

      changes ->
        Alaja.print_info("Applying preset '#{name}'...")

        Enum.each(changes, fn {section, key, value} ->
          Manager.set(section, key, value)
          Alaja.print_info("  [#{section}] #{key} = #{value}")
        end)

        Alaja.print_success("\nPreset '#{name}' applied.")

        cond do
          name == "anthropic" ->
            Alaja.print_info("\nRemember to set your API key:")
            Alaja.print_info("  delfos config set llm api_key sk-ant-YOUR_KEY")

            Alaja.print_info(
              "\nNote: Anthropic does not support embeddings. Embedding will use whatever provider you have configured."
            )

          name in ["openai", "openai-large"] ->
            Alaja.print_info("\nRemember to set your API keys:")
            Alaja.print_info("  delfos config set llm api_key sk-YOUR_KEY")
            Alaja.print_info("  delfos config set embedding api_key sk-YOUR_KEY")

            Alaja.print_warning(
              "\nIf you change dim, recreate the DB: mix ecto.reset && delfos init"
            )

          true ->
            Alaja.print_info("\nMake sure your local servers are running:")
            Alaja.print_info("  llama-run gpt-oss")
            Alaja.print_info("  llama-run embed")
        end
    end
  end

  def run(["preset" | _]) do
    Alaja.print_info("Available presets:\n")

    Enum.each(@presets, fn {name, changes} ->
      Alaja.print_info("  #{name}")
      Enum.each(changes, fn {s, k, v} -> Alaja.print_raw("    [#{s}] #{k} = #{v}\n") end)
      Alaja.print_raw("\n")
    end)
  end

  def run(["setup" | args]) do
    Delfos.CLI.Commands.Setup.run(args)
  end

  def run(["models" | args]) do
    # Inlined: was Delfos.CLI.Commands.Models.run(args)
    # (the Models module was merged into this command)
    cfg_emb = Manager.embedding()
    cfg_llm = Manager.llm()

    section = """
    Active models:

      Embedding:  #{cfg_emb[:provider]}/#{cfg_emb[:model]}
                  #{cfg_emb[:url]} (dim=#{cfg_emb[:dim]})

      LLM:        #{cfg_llm[:provider]}/#{cfg_llm[:model]}
                  #{cfg_llm[:url]}
    """

    output =
      if "--probe" in args do
        section <> "\n\nProbe results:\n" <> Delfos.Config.Diagnostics.summary()
      else
        section
      end

    Alaja.print_raw(output)
  end

  # v2.5.0 (T16): explicit version of the auto-migration that runs
  # silently in llm/0 and embedding/0 (v2.4.0+, commit ccbbedb).
  # Scans config.json for stale cloud provider entries (OpenAI /
  # Anthropic with the wizard-default URL) and reverts them to :local.
  #
  # The auto-migrate is the load-bearing logic that keeps users from
  # accidentally pointing Delfos at api.openai.com after running
  # `delfos config setup llm` with no custom URL — this command
  # is the escape hatch when you want to see exactly what's about
  # to happen or migrate after the fact (e.g. you upgraded from
  # v2.3.x and want to clean up an old config.json).
  def run(["migrate-local" | args]) do
    cfg = Manager.load()
    target_sections = ["embedding", "llm", "summarize"]
    changes = []

    changes =
      Enum.reduce(target_sections, changes, fn section, acc ->
        sub = Map.get(cfg, section, %{}) |> Map.get("url")
        provider = Map.get(cfg, section, %{}) |> Map.get("provider")

        if provider in ["openai", "anthropic"] and Manager.stale_cloud_url?(sub) do
          [{section, provider, sub} | acc]
        else
          acc
        end
      end)

    case changes do
      [] ->
        Alaja.print_success("No stale cloud providers found. Config is clean.")

      _ ->
        Alaja.print_info("Found #{length(changes)} stale cloud provider entries:")

        Enum.each(changes, fn {section, provider, url} ->
          Alaja.print_raw("  [#{section}] provider=#{provider} url=#{url}\n")
        end)

        if "--yes" in args or confirm_migrate?() do
          Enum.each(changes, fn {section, _provider, _url} ->
            Manager.set(section, "provider", "local")

            # Force the URL to the local default for the section.
            local_url =
              case section do
                "embedding" -> "http://127.0.0.1:9998"
                _ -> "http://127.0.0.1:9999"
              end

            Manager.set(section, "url", local_url)
          end)

          Alaja.print_success("Migrated #{length(changes)} section(s) to :local.")
        else
          Alaja.print_info("Cancelled. Re-run with --yes to apply.")
        end
    end
  end

  def run(_) do
    Alaja.print_raw("""

    Usage: delfos config <subcommand>

    Subcommands:
      show                         Show active configuration
      path                         Print the config file path
      init                         Create the config file with defaults
      get <section> <key>          Read a value
      set <section> <key> <value>  Write a value
      preset <name>                Apply a provider preset (local|anthropic|openai|openai-large)
      migrate-local [--yes]        Force-revert stale cloud providers to :local
      setup [db|llm]               Interactive setup wizard (DB / LLM)
      models [--probe]             Show active embedding/LLM models

    Sections: embedding | llm | analysis | indexing | database

    Presets: #{Map.keys(@presets) |> Enum.join(" | ")}

    Examples:
      delfos config show
      delfos config preset local
      delfos config set llm provider anthropic
      delfos config set llm api_key sk-ant-xxxxx
      delfos config set embedding api_key sk-xxxxx
      delfos config get llm model
      delfos config models              # show active models
      delfos config setup db           # DB setup wizard
      delfos config setup llm          # LLM setup wizard
    """)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp suggest_dim_for_provider("openai") do
    Alaja.print_info(
      "\n  For text-embedding-3-small use dim=1536, for text-embedding-3-large use dim=3072"
    )

    Alaja.print_info("  Apply with: delfos config preset openai  (or openai-large)")
  end

  defp suggest_dim_for_provider("local") do
    Alaja.print_info("\n  For mxbai-embed-large use dim=1024, for nomic-embed use dim=768")
  end

  defp suggest_dim_for_provider(_), do: :ok

  defp confirm_migrate? do
    Alaja.Printer.Interactive.question_with_options(
      "Apply the migration?",
      [
        {"Yes, set providers to local", :yes},
        {"No, cancel", :no}
      ],
      color: :cyan,
      default: 1
    ) == :yes
  end
end
