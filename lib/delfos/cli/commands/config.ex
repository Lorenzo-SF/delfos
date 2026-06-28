defmodule Delfos.CLI.Commands.Config do
  @moduledoc """
  Manage Delfos global configuration.

  File: `~/.config/delfos/delfos.conf`

  Subcommands:
    show                       Show the active configuration
    get <section> <key>        Read a value
    set <section> <key> <v>    Write a value
    init                       Create the file with defaults
    preset <name>              Apply a provider preset
    path                       Show the config file path

  All output is rendered via `Alaja` for consistent icon-prefixed messages.
  """

  alias Alaja
  alias Delfos.Config.Manager

  # Presets of the most-used providers
  @presets %{
    "local" => [
      {"embedding", "provider", "local"},
      {"embedding", "url", "http://127.0.0.1:9998"},
      {"embedding", "model", "mxbai-embed-v1"},
      {"embedding", "api_key", "sk-local-dev"},
      {"embedding", "dim", "1024"},
      {"llm", "provider", "local"},
      {"llm", "url", "http://127.0.0.1:8080"},
      {"llm", "model", "thinker"},
      {"llm", "api_key", "sk-local-dev"}
    ],
    "anthropic" => [
      {"llm", "provider", "anthropic"},
      {"llm", "url", "https://api.anthropic.com"},
      {"llm", "model", "claude-sonnet-4-20250514"}
    ],
    "openai" => [
      {"embedding", "provider", "openai"},
      {"embedding", "url", "https://api.openai.com"},
      {"embedding", "model", "text-embedding-3-small"},
      {"embedding", "dim", "1536"},
      {"llm", "provider", "openai"},
      {"llm", "url", "https://api.openai.com"},
      {"llm", "model", "gpt-4o-mini"}
    ],
    "openai-large" => [
      {"embedding", "provider", "openai"},
      {"embedding", "url", "https://api.openai.com"},
      {"embedding", "model", "text-embedding-3-large"},
      {"embedding", "dim", "3072"},
      {"llm", "provider", "openai"},
      {"llm", "url", "https://api.openai.com"},
      {"llm", "model", "gpt-4o"}
    ]
  }

  def run(["wizard" | _]) do
    Alaja.print_raw("\n")
    Delfos.CLI.Commands.Setup.LLM.run(force: true)
  end

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
      # ensure_config_exists is called in load(); force-create the file here
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, default_config_content())
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

  def run(["set", section, key, value | _]) do
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

  def run(["preset", name | _]) do
    case Map.get(@presets, name) do
      nil ->
        Alaja.print_error("Unknown preset: #{name}")
        Alaja.print_info("Available presets: #{Map.keys(@presets) |> Enum.join(", ")}")

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
            Alaja.print_info("  MODEL_ID=thinker bash llm-server.sh")
            Alaja.print_info("  MODEL_ID=embed PORT=9998 bash llm-server.sh")
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

  def run(_) do
    Alaja.print_raw("""

    Usage: delfos config <subcommand>

    Subcommands:
      wizard                       Interactive LLM provider/model setup
      show                         Show active configuration
      path                         Print the config file path
      init                         Create the config file with defaults
      get <section> <key>          Read a value
      set <section> <key> <value>  Write a value
      preset <name>                Apply a provider preset

    Sections: embedding | llm | analysis | indexing

    Presets: #{Map.keys(@presets) |> Enum.join(" | ")}

    Examples:
      delfos config wizard
      delfos config show
      delfos config set llm provider anthropic
      delfos config set llm api_key sk-ant-xxxxx
      delfos config preset openai
      delfos config set embedding api_key sk-xxxxx
      delfos config get llm model
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

  defp default_config_content do
    File.read!(Path.join(:code.priv_dir(:delfos), "delfos.conf.default"))
  rescue
    _ ->
      # Fallback when the priv file is missing
      """
      [embedding]
      provider = "local"
      url      = "http://127.0.0.1:9998"
      model    = "mxbai-embed-v1"
      api_key  = "sk-local-dev"
      dim      = 1024
      batch_size = 32
      timeout_ms = 30000

      [llm]
      provider  = "local"
      url       = "http://127.0.0.1:8080"
      model     = "thinker"
      api_key   = "sk-local-dev"
      timeout_ms = 60000
      max_tokens = 2048

      [analysis]
      churn_max_commits = 1000
      """
  end
end
