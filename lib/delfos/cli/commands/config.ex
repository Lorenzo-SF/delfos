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
  alias Delfos.CLI.Spinner
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

  def run(["show" | args]) do
    if "--json" in args do
      render_show_json()
    else
      # v2.6.0: wrap in spinner for short but noticeable ops
      # (decrypt api_keys, read file). Non-TTY path is a no-op.
      Spinner.with("Loading configuration", fn ->
        Manager.show()
      end)
      |> Alaja.print_raw()
    end
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

  # v2.7.0: `delfos config theme` — view + edit the custom theme.
  #
  # Usage:
  #   delfos config theme show                   # show all effective colours
  #                                              # (defaults + user overrides)
  #   delfos config theme show --json            # machine-readable
  #   delfos config theme set <key> <color>      # write to theme.json
  #   delfos config theme reset [key]            # remove override(s)
  #   delfos config theme path                   # print theme.json location
  #
  # `<color>` accepts the same formats as the theme.json file:
  # hex strings ("#FF0000"), CSS names ("red"), RGB arrays ("[255,0,0]"),
  # RGB objects, or "theme:<key>" references.
  def run(["theme", "show"]) do
    print_theme()
  end

  def run(["theme", "show", "--json"]) do
    render_theme_json()
  end

  def run(["theme", "set", key, color]) when is_binary(key) and is_binary(color) do
    set_theme_color(key, color)
  end

  def run(["theme", "reset"]) do
    reset_all_theme()
  end

  def run(["theme", "reset", key]) when is_binary(key) do
    reset_theme_color(key)
  end

  def run(["theme", "path"]) do
    Alaja.print_raw(Delfos.Theme.theme_file_path() <> "\n")
  end

  def run(["theme" | _]) do
    Alaja.print_raw("""
    Usage:
      delfos config theme show [--json]    Show effective theme (defaults + overrides)
      delfos config theme set KEY COLOR    Add or update one theme colour
      delfos config theme reset [KEY]     Remove overrides (or one)
      delfos config theme path            Print theme.json path

    Colours accept: #RRGGBB, #RGB, CSS names, [r,g,b], or "theme:KEY"
    """)
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

  # v2.6.0: `delfos config show --json` renders the decrypted config
  # as syntax-highlighted JSON via `Alaja.Components.Json.render/2`.
  # Pre-v2.6.0, the JSON path was raw `Jason.encode!` (no colour, no
  # hierarchy cues) and didn't surface the sections that Manager
  # knows about at runtime but the JSON loader doesn't necessarily
  # materialise (e.g. `[mcp]` is added by Manager at boot).
  defp render_show_json do
    # Build a complete snapshot. We read the on-disk JSON directly
    # (via Manager.load/0, which decrypts api_key fields) and merge
    # in any runtime-only sections like [mcp].
    cfg = Manager.load()
    cfg = Map.put(cfg, "mcp", Manager.mcp_section())

    buf =
      Alaja.Components.Json.render(cfg,
        key_color: {0, 180, 216},
        string_color: {0, 200, 80},
        number_color: {220, 180, 0},
        boolean_color: {255, 180, 100},
        null_color: {100, 100, 100},
        punctuation_color: {180, 180, 180}
      )

    Alaja.print_raw(Alaja.Buffer.to_iodata(buf))
    Alaja.print_raw("\n")
  end

  # ──────────────────────────────────────────────────────────────────
  # Theme helpers (v2.7.0)
  # ──────────────────────────────────────────────────────────────────

  defp print_theme do
    body =
      Pote.default_colors()
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map_join("\n", fn {key, default_rgb} ->
        user_rgb = Map.get(Delfos.Theme.theme(), key)
        rgb = user_rgb || default_rgb
        {r, g, b} = rgb
        swatch = "#{Alaja.ANSI.fg(r, g, b)}█████#{Alaja.ANSI.reset()}"
        marker = if user_rgb, do: " (override)", else: ""
        "  #{String.pad_trailing(to_string(key), 16)} #{swatch}  #{inspect(rgb)}#{marker}"
      end)

    overrides = Delfos.Theme.user_overrides()

    header =
      if overrides == [] do
        "No user overrides — using Pote defaults. Edit ~/.config/delfos/theme.json to customise."
      else
        "User overrides (#{length(overrides)}): #{inspect(Enum.map(overrides, fn {k, _} -> k end))}"
      end

    Alaja.Components.Box.print(body <> "\n\n" <> header,
      title: "Delfos theme",
      border: :rounded,
      border_color: {0, 180, 216},
      padding: 1
    )
  end

  defp render_theme_json do
    merged =
      Pote.default_colors()
      |> Map.new(fn {k, default_rgb} ->
        {k, Map.get(Delfos.Theme.theme(), k) || default_rgb}
      end)

    Alaja.Components.Json.render(merged)
    |> Alaja.Buffer.to_iodata()
    |> IO.write()

    IO.puts("")
  end

  defp set_theme_color(key, color_str) do
    case parse_theme_value(color_str) do
      {:ok, rgb} ->
        write_theme_overrides(Map.put(load_overrides(), safe_atom(key), rgb))
        Alaja.print_success("Set #{key} = #{inspect(rgb)}")

      {:error, reason} ->
        Alaja.print_error("Invalid colour: #{reason}")

        raise Delfos.CLI.Abort,
          message: "invalid colour #{inspect(color_str)}",
          code: 1
    end
  end

  defp reset_theme_color(key) do
    overrides = load_overrides()
    atom = safe_atom(key)

    case Map.pop(overrides, atom) do
      {nil, _} ->
        Alaja.print_info("#{key} is not overridden (no change).")

      {_removed, rest} ->
        write_theme_overrides(rest)
        Alaja.print_success("Removed override for #{key}")
    end
  end

  defp reset_all_theme do
    case File.rm(Delfos.Theme.theme_file_path()) do
      :ok -> Alaja.print_success("Theme reset to Pote defaults.")
      {:error, :enoent} -> Alaja.print_info("No theme file — already at defaults.")
      {:error, reason} -> Alaja.print_error("Failed to remove theme file: #{inspect(reason)}")
    end
  end

  defp parse_theme_value(color_str) do
    case Pote.Orchestrator.parse_color(color_str) do
      {:ok, rgb} when is_tuple(rgb) and tuple_size(rgb) == 3 -> {:ok, rgb}
      {:ok, _} -> {:error, "parsed to a non-RGB value"}
      {:error, _} -> {:error, "Pote couldn't parse #{inspect(color_str)}"}
    end
  end

  defp load_overrides do
    case File.read(Delfos.Theme.theme_file_path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, decoded} when is_map(decoded) ->
            decoded
            |> Map.new(fn {k, v} -> {safe_atom(k), parse_theme_value_or_skip(v)} end)
            |> Enum.reject(fn {_k, v} -> v == :skip end)
            |> Map.new()

          _ ->
            %{}
        end

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Alaja.print_warning("theme.json unreadable (#{inspect(reason)}); starting fresh")
        %{}
    end
  end

  defp parse_theme_value_or_skip(v) do
    case parse_theme_value(safe_stringify(v)) do
      {:ok, rgb} -> rgb
      _ -> :skip
    end
  end

  defp safe_stringify(v) when is_binary(v), do: v
  defp safe_stringify(v) when is_integer(v), do: Integer.to_string(v)
  defp safe_stringify(v), do: inspect(v)

  defp safe_atom(key) when is_atom(key), do: key

  defp safe_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> :"#{key}"
      _ -> :"#{key}"
    end
  end

  defp safe_atom(_), do: nil

  defp write_theme_overrides(overrides) do
    path = Delfos.Theme.theme_file_path()
    File.mkdir_p!(Path.dirname(path))

    serializable =
      overrides
      |> Map.new(fn {k, {r, g, b}} -> {Atom.to_string(k), "#{r},#{g},#{b}"} end)

    File.write!(path, Jason.encode!(serializable, pretty: true))

    # Reset the in-process cache so the new values take effect.
    Process.delete({Delfos.Theme, :theme})
  end
end
