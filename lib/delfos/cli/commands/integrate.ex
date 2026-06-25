defmodule Delfos.CLI.Commands.Integrate do
  alias Alaja

  @moduledoc """
  Configura automáticamente la integración de Delfos con agentes de IA.

  Agentes soportados:
    claude-code  — Configura ~/.claude.json y ~/.claude/CLAUDE.md
    opencode     — Configura ~/.config/opencode/config.json y AGENTS.md
    cursor       — Configura .cursor/mcp.json en el proyecto
    aider        — Configura .aider.conf.yml en el proyecto
    codex        — Configura ~/.codex/config.yaml
    zed          — Configura ~/.config/zed/settings.json
    all          — Todos los anteriores (interactive)
  """

  @claude_md_instructions """
  ## Delfos Code Intelligence

  This project has Delfos initialized. Use Delfos MCP tools for code exploration.

  ### ALWAYS use Delfos FIRST for:
  - Finding how something works → `delfos_context(task)`
  - Finding a specific symbol → `delfos_search(query)` then `delfos_symbol(name)`
  - Before editing a function → `delfos_symbol(name)` + `delfos_impact(name)`
  - Tracing call flow → `delfos_callers(name)` / `delfos_callees(name)`

  ### NEVER read files directly when Delfos can answer
  Delfos returns complete code in the SYMBOL response. Do not re-read the file
  unless you need something beyond what Delfos returned.

  ### Response format
  Delfos responses are compact and information-dense. The fields are:
  - SYMBOL/KIND/FILE: identity and location
  - SUMMARY: LLM-generated description (trust this)
  - SPEC: signature or @spec
  - CALLERS/CALLEES: graph edges (n = count)
  - RISK: debt_score, instability, churn, in_cycle (⚠ if in_cycle=true)
  - RELATED: semantically similar symbols with cosine similarity score
  - CODE: actual source code
  """

  @help """
  USAGE
      delfos integrate [agent] [flags]

  Wire Delfos MCP into an AI coding agent. Writes the agent's config file
  and (for some agents) generates AGENTS.md with Delfos-specific
  instructions.

  AGENTS
      claude-code    ~/.claude.json + ~/.claude/CLAUDE.md
      opencode       ~/.config/opencode/config.json + .opencode/AGENTS.md
      cursor         .cursor/mcp.json + .cursorrules
      aider          .aider.conf.yml + AGENTS.md
      codex          ~/.codex/config.yaml
      zed            ~/.config/zed/settings.json
      all            All of the above (interactive)

  FLAGS
      --yes             Skip confirmation prompts
      --project <dir>   Project directory (default: cwd)

  After running, start the MCP server with: delfos serve --mcp
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, switches: [yes: :boolean, project: :string])
    target = List.first(rest) || "all"
    auto_yes = opts[:yes] || false
    project_path = opts[:project] || File.cwd!()

    Alaja.print_raw("\n=== DELFOS INTEGRATE ===" <> "\n")
    Alaja.print_info("Configurando integración con agentes de IA...\n")

    agents =
      case target do
        "all" -> ["claude-code", "opencode", "cursor", "aider", "codex", "zed"]
        name -> [name]
      end

    Enum.each(agents, fn agent ->
      if auto_yes or confirm?("¿Configurar #{agent}?") do
        case configure_agent(agent, project_path) do
          :ok ->
            Alaja.print_success("#{agent} configured")

          {:ok, msg} ->
            Alaja.print_success("#{agent}: #{msg}")

          {:skip, reason} ->
            Alaja.print_info("#{agent}: #{reason}")

          {:error, reason} ->
            Alaja.print_error("#{agent}: #{reason}")
        end
      else
        Alaja.print_info("  - #{agent}: omitido")
      end
    end)

    Alaja.print_success("\nIntegration complete.")
    Alaja.print_info("Make sure the MCP server is running:")
    Alaja.print_info("  delfos serve --mcp")
    Alaja.print_info("\nOr add delfos to your shell startup for automatic launch.")
  end

  # ---------------------------------------------------------------------------
  # Configuración por agente
  # ---------------------------------------------------------------------------

  defp configure_agent("claude-code", _project_path) do
    configure_claude_code()
  end

  defp configure_agent("opencode", project_path) do
    configure_opencode(project_path)
  end

  defp configure_agent("cursor", project_path) do
    configure_cursor(project_path)
  end

  defp configure_agent("aider", project_path) do
    configure_aider(project_path)
  end

  defp configure_agent("codex", _project_path) do
    configure_codex()
  end

  defp configure_agent("zed", _project_path) do
    configure_zed()
  end

  defp configure_agent(name, _), do: {:error, "Agente desconocido: #{name}"}

  # ---------------------------------------------------------------------------
  # Claude Code (~/.claude.json + ~/.claude/CLAUDE.md)
  # ---------------------------------------------------------------------------

  defp configure_claude_code do
    claude_json_path = Path.expand("~/.claude.json")
    claude_md_path = Path.expand("~/.claude/CLAUDE.md")

    # 1. Configurar MCP en ~/.claude.json
    current =
      case File.read(claude_json_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, parsed} -> parsed
            {:error, reason} -> raise "Existing #{claude_json_path} is not valid JSON: #{inspect(reason)}"
          end

        {:error, :enoent} -> %{}
        {:error, reason} -> raise "Cannot read #{claude_json_path}: #{inspect(reason)}"
      end

    mcp_servers = Map.get(current, "mcpServers", %{})

    updated =
      Map.put(
        current,
        "mcpServers",
        Map.put(mcp_servers, "delfos", %{
          "type" => "stdio",
          "command" => delfos_bin(),
          "args" => ["serve", "--mcp"]
        })
      )

    File.mkdir_p!(Path.dirname(claude_json_path))
    safe_write(claude_json_path, Jason.encode!(updated, pretty: true))

    # Sanity check: read back and parse
    with {:ok, written} <- File.read(claude_json_path),
         {:ok, _} <- Jason.decode(written) do
      :ok
    else
      _ -> {:error, "Failed to verify written config"}
    end

    # 2. Añadir instrucciones a ~/.claude/CLAUDE.md
    File.mkdir_p!(Path.dirname(claude_md_path))

    existing = File.read(claude_md_path) |> elem(1) |> then(&(&1 || ""))

    unless String.contains?(existing, "Delfos Code Intelligence") do
      safe_write(claude_md_path, existing <> "\n" <> @claude_md_instructions)
    end

    # 3. Configurar auto-allow en ~/.claude/settings.json
    settings_path = Path.expand("~/.claude/settings.json")

    settings = read_json_or_empty(settings_path)

    permissions = Map.get(settings, "permissions", %{})
    allow = Map.get(permissions, "allow", [])

    delfos_tools = [
      "mcp__delfos__delfos_search",
      "mcp__delfos__delfos_symbol",
      "mcp__delfos__delfos_context",
      "mcp__delfos__delfos_callers",
      "mcp__delfos__delfos_callees",
      "mcp__delfos__delfos_impact",
      "mcp__delfos__delfos_audit",
      "mcp__delfos__delfos_files"
    ]

    new_allow = (allow ++ delfos_tools) |> Enum.uniq()
    new_settings = Map.put(settings, "permissions", Map.put(permissions, "allow", new_allow))
    safe_write(settings_path, Jason.encode!(new_settings, pretty: true))

    :ok
  end

  # ---------------------------------------------------------------------------
  # OpenCode (~/.config/opencode/config.json + proyecto AGENTS.md)
  # ---------------------------------------------------------------------------

  defp configure_opencode(project_path) do
    config_path = Path.expand("~/.config/opencode/config.json")

    current = read_json_or_empty(config_path)

    mcp = Map.get(current, "mcp", %{})

    updated =
      Map.put(
        current,
        "mcp",
        Map.put(mcp, "delfos", %{
          "command" => delfos_bin(),
          "args" => ["serve", "--mcp"],
          "type" => "local"
        })
      )

    File.mkdir_p!(Path.dirname(config_path))
    safe_write(config_path, Jason.encode!(updated, pretty: true))

    verify_json(config_path)

    # AGENTS.md en el proyecto
    agents_md_path = Path.join([project_path, ".opencode", "AGENTS.md"])
    File.mkdir_p!(Path.dirname(agents_md_path))

    existing =
      File.read(agents_md_path)
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    unless String.contains?(existing, "Delfos Code Intelligence") do
      safe_write(agents_md_path, existing <> "\n" <> @claude_md_instructions)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Cursor (.cursor/mcp.json en el proyecto)
  # ---------------------------------------------------------------------------

  defp configure_cursor(project_path) do
    mcp_path = Path.join(project_path, ".cursor/mcp.json")

    current = read_json_or_empty(mcp_path)

    mcp_servers = Map.get(current, "mcpServers", %{})

    updated =
      Map.put(
        current,
        "mcpServers",
        Map.put(mcp_servers, "delfos", %{
          "command" => delfos_bin(),
          "args" => ["serve", "--mcp"]
        })
      )

    File.mkdir_p!(Path.dirname(mcp_path))
    safe_write(mcp_path, Jason.encode!(updated, pretty: true))

    verify_json(mcp_path)

    # Cursor 0.45+ usa reglas MDC en .cursor/rules/*.mdc (frontmatter YAML +
    # Markdown body). El formato legacy .cursorrules sigue funcionando pero
    # está deprecado. Escribimos el formato nuevo.
    rules_dir = Path.join(project_path, ".cursor/rules")
    File.mkdir_p!(rules_dir)
    rules_path = Path.join(rules_dir, "delfos.mdc")

    frontmatter = "---\n" <>
                   "description: Delfos code intelligence (MCP search, impact, audit)\n" <>
                   "alwaysApply: true\n" <>
                   "---\n\n"

    existing =
      File.read(rules_path)
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    unless String.contains?(existing, "Delfos Code Intelligence") do
      safe_write(rules_path, frontmatter <> @claude_md_instructions)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Aider (.aider.conf.yml en el proyecto)
  # ---------------------------------------------------------------------------

  defp configure_aider(project_path) do
    conf_path = Path.join(project_path, ".aider.conf.yml")
    agents_md = Path.join(project_path, "AGENTS.md")

    # Backup AGENTS.md si existe — nunca sobreescribimos trabajo del usuario
    backup_msg =
      case File.read(agents_md) do
        {:ok, content} ->
          if String.contains?(content, "Delfos Code Intelligence") do
            "AGENTS.md ya contiene instrucciones de Delfos (sin cambios)"
          else
            backup_path = backup_for(agents_md)
            File.cp!(agents_md, backup_path)
            safe_write(agents_md, content <> "\n" <> @claude_md_instructions)

            "AGENTS.md actualizado (backup en #{backup_path})"
          end

        {:error, :enoent} ->
          safe_write(agents_md, @claude_md_instructions)
          "AGENTS.md creado"
      end

    merge_aider_read(conf_path)
    {:ok, backup_msg}
  end

  defp merge_aider_read(conf_path) do
    existing_yaml =
      case File.read(conf_path) do
        {:ok, c} ->
          case YamlElixir.read_from_string(c, merge_anchors: false, atoms: false) do
            {:ok, parsed} when is_map(parsed) -> parsed
            _ -> %{}
          end

        {:error, :enoent} ->
          %{}

        {:error, _} ->
          %{}
      end

    current_read =
      case Map.get(existing_yaml, "read") do
        list when is_list(list) -> Enum.map(list, &to_string/1)
        _ -> []
      end

    if "AGENTS.md" in current_read do
      :ok
    else
      new_read = current_read ++ ["AGENTS.md"]

      # Serialize the read list back, stripping the YAML lib's document
      # marker. We rebuild the file by hand to keep diffs minimal.
      other_yaml =
        existing_yaml
        |> Map.delete("read")
        |> YamlElixir.write_to_string()

      list_block =
        new_read
        |> Enum.map_join("\n", &"  - #{&1}")
        |> (&"read:\n#{&1}\n").()

      safe_write(conf_path, other_yaml <> "\n# Delfos code intelligence\n" <> list_block)
    end
  end

  # ---------------------------------------------------------------------------
  # Codex (~/.codex/config.toml — yes, TOML, not YAML; top-level key is
  # [mcp_servers] not [mcpServers])
  # ---------------------------------------------------------------------------

  defp configure_codex do
    config_path = Path.expand("~/.codex/config.toml")
    File.mkdir_p!(Path.dirname(config_path))

    existing =
      case File.read(config_path) do
        {:ok, c} ->
          case Toml.decode(c) do
            {:ok, _} -> c
            {:error, reason} ->
              raise "#{config_path} is not valid TOML: #{inspect(reason)}"
          end

        {:error, :enoent} ->
          ""

        {:error, reason} ->
          raise "Cannot read #{config_path}: #{inspect(reason)}"
      end

    has_delfos? =
      case Toml.decode(existing) do
        {:ok, %{"mcp_servers" => %{"delfos" => _}}} -> true
        _ -> false
      end

    if has_delfos? do
      {:skip, "Ya configurado en ~/.codex/config.toml"}
    else
      addition = """

      # Delfos MCP integration
      [mcp_servers.delfos]
      command = "#{delfos_bin()}"
      args = ["serve", "--mcp"]
      """

      safe_write(config_path, existing <> addition)

      # Sanity check: round-trip the TOML
      case Toml.decode_file(config_path) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, "Failed to verify #{config_path}: #{inspect(reason)}"}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Zed (~/.config/zed/settings.json)
  # ---------------------------------------------------------------------------

  defp configure_zed do
    settings_path = Path.expand("~/.config/zed/settings.json")

    current = read_json_or_empty(settings_path)

    context_servers = Map.get(current, "context_servers", %{})

    updated =
      Map.put(
        current,
        "context_servers",
        Map.put(context_servers, "delfos", %{
          "command" => %{
            "path" => delfos_bin(),
            "args" => ["serve", "--mcp"]
          }
        })
      )

    File.mkdir_p!(Path.dirname(settings_path))
    safe_write(settings_path, Jason.encode!(updated, pretty: true))

    verify_json(settings_path)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp delfos_bin do
    # Intenta encontrar el binario delfos en el PATH
    case System.find_executable("delfos") do
      nil -> "delfos"
      path -> path
    end
  end

  defp confirm?(message) do
    Alaja.print_info("  #{message} [s/N] ")
    answer = IO.gets("") |> String.trim() |> String.downcase()
    answer in ["s", "si", "sí", "y", "yes"]
  end

  defp read_json_or_empty(path) do
    case File.read(path) do
      {:ok, ""} ->
        %{}

      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, parsed} -> parsed
          {:error, reason} -> raise "#{path} is not valid JSON: #{inspect(reason)}"
        end

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        raise "Cannot read #{path}: #{inspect(reason)}"
    end
  end

  defp verify_json(path) do
    with {:ok, written} <- File.read(path),
         {:ok, _} <- Jason.decode(written) do
      :ok
    else
      {:error, reason} -> {:error, "Failed to verify #{path}: #{inspect(reason)}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Safe writes with timestamp backup
  # ---------------------------------------------------------------------------

  @doc """
  Writes `content` to `path` only after backing up any existing file
  at that location to `<path>.bak-<unix_seconds>`.

  If the target file does not exist, the write proceeds without a
  backup (there is nothing to preserve).

  If the existing file is empty (zero bytes), no backup is created
  — there is no user content to preserve.
  """
  @spec safe_write(Path.t(), iodata()) :: :ok | {:error, File.posix()}
  def safe_write(path, content) when is_binary(path) do
    cond do
      not File.exists?(path) ->
        File.write(path, content)

      true ->
        case File.read(path) do
          {:ok, ""} ->
            File.write(path, content)

          {:ok, _existing} ->
            backup = backup_for(path)
            File.cp!(path, backup)
            File.write(path, content)
        end
    end
  end

  defp backup_for(path) do
    path <> ".bak-" <> Integer.to_string(:os.system_time(:second))
  end
end
