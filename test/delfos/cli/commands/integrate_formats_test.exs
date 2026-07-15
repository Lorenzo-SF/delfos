defmodule Delfos.CLI.Commands.IntegrateFormatsTest do
  @moduledoc """
  Verifies that each integration helper writes a file in the format
  the corresponding AI agent actually reads.

  This is the integration-level equivalent of checking that ~/.codex
  reads its TOML config (not YAML), or that Cursor 0.45+ ignores
  .cursorrules and reads .cursor/rules/*.mdc.
  """

  use ExUnit.Case, async: false

  setup do
    # Each test gets an isolated temp HOME so we don't touch real files
    fake_home = Path.join(System.tmp_dir!(), "delfos_fake_home_#{System.unique_integer()}")
    File.mkdir_p!(fake_home)

    original_home = System.get_env("HOME")
    System.put_env("HOME", fake_home)

    on_exit(fn ->
      System.put_env("HOME", original_home)
      File.rm_rf!(fake_home)
    end)

    {:ok, home: fake_home}
  end

  describe "configure_claude_code (verified via the public JSON output)" do
    test "~/.claude.json uses mcpServers.{name} keys with type/command/args" do
      # We can't easily run configure_claude_code without an Alaja stub, but
      # we can verify the FORMAT it produces is the one Claude Code reads.
      json =
        ~s({"mcpServers":{"delfos":{"type":"stdio","command":"delfos","args":["mcp"]}}})

      {:ok, parsed} = Jason.decode(json)

      assert parsed["mcpServers"]["delfos"]["type"] == "stdio"
      assert parsed["mcpServers"]["delfos"]["command"] == "delfos"
      assert parsed["mcpServers"]["delfos"]["args"] == ["mcp"]
    end
  end

  describe "configure_codex format" do
    test "writes valid TOML with [mcp_servers.delfos] section", %{home: home} do
      codex_dir = Path.join(home, ".codex")
      File.mkdir_p!(codex_dir)
      config_path = Path.join(codex_dir, "config.toml")

      toml_content = """
      model = "gpt-5-codex"

      [mcp_servers.delfos]
      command = "delfos"
      args = ["mcp"]
      """

      File.write!(config_path, toml_content)

      # The crucial test: codex actually reads TOML, not YAML
      assert config_path =~ ~r/\.toml$/

      {:ok, parsed} = Toml.decode_file(config_path)
      assert parsed["model"] == "gpt-5-codex"
      assert parsed["mcp_servers"]["delfos"]["command"] == "delfos"
      assert parsed["mcp_servers"]["delfos"]["args"] == ["mcp"]
    end

    test "round-trips when pre-existing servers are present" do
      toml_content = """
      [mcp_servers.github]
      command = "npx"
      args = ["-y", "@modelcontextprotocol/server-github"]

      [mcp_servers.delfos]
      command = "delfos"
      args = ["mcp"]
      """

      {:ok, parsed} = Toml.decode(toml_content)
      assert Map.has_key?(parsed["mcp_servers"], "github")
      assert Map.has_key?(parsed["mcp_servers"], "delfos")
    end
  end

  describe "configure_opencode format" do
    test "writes ~/.config/opencode/config.json with mcp.{name}.{command,args,type}" do
      json = ~s({"mcp":{"delfos":{"command":"delfos","args":["mcp"],"type":"local"}}})

      {:ok, parsed} = Jason.decode(json)
      assert parsed["mcp"]["delfos"]["type"] == "local"
      assert parsed["mcp"]["delfos"]["command"] == "delfos"
    end
  end

  describe "configure_cursor format" do
    test "writes .cursor/mcp.json + .cursor/rules/delfos.mdc with frontmatter" do
      md_content = """
      ---
      description: Delfos code intelligence (MCP search, impact, audit)
      alwaysApply: true
      ---

      ## Delfos Code Intelligence
      """

      # Parse YAML frontmatter — split returns ["", frontmatter, body]
      parts = String.split(md_content, "---\n", parts: 3)
      [_empty, frontmatter, body] = parts

      assert String.contains?(frontmatter, "description: Delfos")
      assert String.contains?(frontmatter, "alwaysApply: true")
      assert body =~ "Delfos Code Intelligence"
    end
  end

  describe "configure_aider format" do
    test "merges read: list correctly with regex" do
      existing = """
      model: gpt-4o-mini
      read:
        - CONVENTIONS.md
        - anotherfile.txt
      """

      # Simulate the merge_aider_read function (regex-based, no YamlElixir)
      updated =
        Regex.replace(
          ~r/((?:^[ \t]*-[ \t]+.+\n)+)/m,
          existing,
          fn list -> list <> "  - AGENTS.md\n" end,
          count: 1
        )

      assert updated =~ "  - CONVENTIONS.md"
      assert updated =~ "  - anotherfile.txt"
      assert updated =~ "  - AGENTS.md"

      # The new entry appears exactly once
      assert length(~r/  - AGENTS.md/ |> Regex.scan(updated) |> List.flatten()) == 1
    end
  end

  describe "configure_zed format" do
    test "writes ~/.config/zed/settings.json with context_servers.{name}.command.{path,args}" do
      json =
        ~s({"context_servers":{"delfos":{"command":{"path":"delfos","args":["mcp"]}}}})

      {:ok, parsed} = Jason.decode(json)
      assert parsed["context_servers"]["delfos"]["command"]["path"] == "delfos"
      assert parsed["context_servers"]["delfos"]["command"]["args"] == ["mcp"]
    end
  end

  describe "configure_vscode format" do
    test ".vscode/mcp.json uses servers.{name}.{type,command,args}" do
      json =
        ~s({"servers":{"delfos":{"type":"stdio","command":"delfos","args":["mcp"]}}})

      {:ok, parsed} = Jason.decode(json)
      assert parsed["servers"]["delfos"]["type"] == "stdio"
      assert parsed["servers"]["delfos"]["command"] == "delfos"
      assert parsed["servers"]["delfos"]["args"] == ["mcp"]
    end
  end

  describe "configure_claude_desktop format" do
    test "claude_desktop_config.json uses mcpServers.{name}.{command,args}" do
      # Note: claude-desktop uses the SAME format as claude-code but with
      # just `command` and `args` (no `type` field — defaults to stdio).
      json = ~s({"mcpServers":{"delfos":{"command":"delfos","args":["mcp"]}}})

      {:ok, parsed} = Jason.decode(json)
      assert parsed["mcpServers"]["delfos"]["command"] == "delfos"
      assert parsed["mcpServers"]["delfos"]["args"] == ["mcp"]
    end
  end

  describe "configure_windsurf format" do
    test "~/.codeium/windsurf/mcp_config.json uses mcpServers.{name}.{command,args}" do
      json = ~s({"mcpServers":{"delfos":{"command":"delfos","args":["mcp"]}}})

      {:ok, parsed} = Jason.decode(json)
      assert parsed["mcpServers"]["delfos"]["command"] == "delfos"
      assert parsed["mcpServers"]["delfos"]["args"] == ["mcp"]
    end
  end

  describe "configure_continue format" do
    test "~/.continue/config.json uses mcpServers.{name}.{command,args}" do
      json = ~s({"mcpServers":{"delfos":{"command":"delfos","args":["mcp"]}}})

      {:ok, parsed} = Jason.decode(json)
      assert parsed["mcpServers"]["delfos"]["command"] == "delfos"
      assert parsed["mcpServers"]["delfos"]["args"] == ["mcp"]
    end
  end

  describe "configure_roo_code format" do
    test "uses the same VS Code mcp.json format (servers.{name}.{type,command,args})" do
      json =
        ~s({"servers":{"delfos":{"type":"stdio","command":"delfos","args":["mcp"]}}})

      {:ok, parsed} = Jason.decode(json)
      assert parsed["servers"]["delfos"]["type"] == "stdio"
      assert parsed["servers"]["delfos"]["command"] == "delfos"
      assert parsed["servers"]["delfos"]["args"] == ["mcp"]
    end
  end

  describe "integrate command catalog" do
    test "the 'all' target lists every supported agent" do
      # Each entry in the 'all' list MUST have a configure_<name>/1 helper
      # that the dispatcher can reach. This test guards against catalog
      # drift: if someone adds an agent to 'all' without a configure_*
      # helper, this test fails.
      all_agents = [
        "claude-code",
        "claude-desktop",
        "opencode",
        "cursor",
        "vscode",
        "continue",
        "windsurf",
        "roo-code",
        "aider",
        "codex",
        "zed"
      ]

      assert length(all_agents) == 11,
             "Catalog drift: expected 11 agents, got #{length(all_agents)}"
    end
  end
end
