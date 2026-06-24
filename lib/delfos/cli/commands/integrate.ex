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
        {:ok, content} -> Jason.decode!(content)
        _ -> %{}
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
    File.write!(claude_json_path, Jason.encode!(updated, pretty: true))

    # 2. Añadir instrucciones a ~/.claude/CLAUDE.md
    File.mkdir_p!(Path.dirname(claude_md_path))

    existing = File.read(claude_md_path) |> elem(1) |> then(&(&1 || ""))

    unless String.contains?(existing, "Delfos Code Intelligence") do
      File.write!(claude_md_path, existing <> "\n" <> @claude_md_instructions)
    end

    # 3. Configurar auto-allow en ~/.claude/settings.json
    settings_path = Path.expand("~/.claude/settings.json")

    settings =
      case File.read(settings_path) do
        {:ok, c} -> Jason.decode!(c)
        _ -> %{}
      end

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
    File.write!(settings_path, Jason.encode!(new_settings, pretty: true))

    :ok
  end

  # ---------------------------------------------------------------------------
  # OpenCode (~/.config/opencode/config.json + proyecto AGENTS.md)
  # ---------------------------------------------------------------------------

  defp configure_opencode(project_path) do
    config_path = Path.expand("~/.config/opencode/config.json")

    current =
      case File.read(config_path) do
        {:ok, c} -> Jason.decode!(c)
        _ -> %{}
      end

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
    File.write!(config_path, Jason.encode!(updated, pretty: true))

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
      File.write!(agents_md_path, existing <> "\n" <> @claude_md_instructions)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Cursor (.cursor/mcp.json en el proyecto)
  # ---------------------------------------------------------------------------

  defp configure_cursor(project_path) do
    mcp_path = Path.join(project_path, ".cursor/mcp.json")

    current =
      case File.read(mcp_path) do
        {:ok, c} -> Jason.decode!(c)
        _ -> %{}
      end

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
    File.write!(mcp_path, Jason.encode!(updated, pretty: true))

    # Cursor también respeta .cursorrules
    rules_path = Path.join(project_path, ".cursorrules")

    existing =
      File.read(rules_path)
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    unless String.contains?(existing, "Delfos") do
      File.write!(rules_path, existing <> "\n" <> String.slice(@claude_md_instructions, 0, 600))
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Aider (.aider.conf.yml en el proyecto)
  # ---------------------------------------------------------------------------

  defp configure_aider(project_path) do
    conf_path = Path.join(project_path, ".aider.conf.yml")

    existing =
      File.read(conf_path)
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    agents_md = Path.join(project_path, "AGENTS.md")

    # Escribir AGENTS.md con instrucciones de Delfos
    File.write!(agents_md, @claude_md_instructions)

    # Añadir --read AGENTS.md al config de aider si no está
    if not String.contains?(existing, "AGENTS.md") do
      addition = "\n# Delfos code intelligence\nread:\n  - AGENTS.md\n"
      File.write!(conf_path, existing <> addition)
    end

    {:ok, "AGENTS.md creado. Aider lo leerá automáticamente si está en .aider.conf.yml"}
  end

  # ---------------------------------------------------------------------------
  # Codex (~/.codex/config.yaml)
  # ---------------------------------------------------------------------------

  defp configure_codex do
    config_path = Path.expand("~/.codex/config.yaml")
    File.mkdir_p!(Path.dirname(config_path))

    existing =
      File.read(config_path)
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    if String.contains?(existing, "delfos") do
      {:skip, "Ya configurado en ~/.codex/config.yaml"}
    else
      addition = """

      # Delfos MCP integration
      mcp_servers:
        delfos:
          command: #{delfos_bin()}
          args: ["serve", "--mcp"]
      """

      File.write!(config_path, existing <> addition)
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Zed (~/.config/zed/settings.json)
  # ---------------------------------------------------------------------------

  defp configure_zed do
    settings_path = Path.expand("~/.config/zed/settings.json")

    current =
      case File.read(settings_path) do
        {:ok, c} -> Jason.decode!(c)
        _ -> %{}
      end

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
    File.write!(settings_path, Jason.encode!(updated, pretty: true))
    :ok
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
end
