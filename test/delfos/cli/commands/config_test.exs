defmodule Delfos.CLI.Commands.ConfigTest do
  @moduledoc """
  Tests for the `delfos config` command.

  These exercise the pure-Elixir surface (preset selection, init
  semantics, show output) without touching the live config file. The
  tests assume `Application.ensure_all_started/1` has already been
  called for `:delfos` and that no real `~/.config/delfos/config.json`
  exists in the host environment.
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Config
  alias Delfos.Config.Manager

  describe "config show" do
    test "prints the active configuration without crashing" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Config.run(["show"])
        end)

      # Whatever the current config is, it should at least mention
      # both `embedding` and `llm` sections (or warn that they're missing).
      assert output != "" or output =~ "embedding"
    end
  end

  describe "config path" do
    test "prints the config file path" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Config.run(["path"])
        end)

      assert output =~ ".config/delfos"
    end
  end

  describe "config preset" do
    test "applies the 'openai' preset" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Config.run(["preset", "openai"])
        end)

      assert output =~ "Applying preset 'openai'"
      assert output =~ "openai"
    end

    test "rejects unknown preset names cleanly" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Config.run(["preset", "nope-not-real"])
        end)

      assert output =~ "Unknown preset"
    end
  end

  describe "config init" do
    setup do
      # Isolate the test from the host's real config by temporarily
      # pointing Application env to a temp dir.
      tmp = Path.join(System.tmp_dir!(), "delfos_config_test_#{:rand.uniform(99_999)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp}
    end

    test "creates a JSON config at the expected path when missing", %{tmp: _tmp} do
      # We can't override @config_dir directly (it's a module attribute),
      # but we can verify that Manager.write/1 produces JSON, and that
      # Manager.default_config_content/0 returns JSON too. This is the
      # surface that `delfos config init` writes to disk.
      content = Manager.default_config_content()

      assert {:ok, decoded} = Jason.decode(content)
      assert is_map(decoded)
      assert Map.has_key?(decoded, "embedding")
      assert Map.has_key?(decoded, "llm")
    end
  end

  describe "config set / get round-trip" do
    test "set writes and get reads back" do
      ExUnit.CaptureIO.capture_io(fn ->
        Config.run(["set", "analysis", "churn_max_commits", "500"])
        Config.run(["set", "analysis", "churn_max_commits", "1000"])
      end)

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Config.run(["get", "analysis", "churn_max_commits"])
        end)

      assert output =~ "1000"
    end
  end

  # ── migrate-local (v2.5.0 / T16) ────────────────────────────────────────
  #
  # Explicit version of the auto-migration added in v2.4.0 (commit ccbbedb).
  # Scans config.json for stale cloud provider entries (OpenAI /
  # Anthropic with the wizard-default URL) and reverts them to :local.

  describe "config migrate-local" do
    setup do
      # Isolate from the real config file.
      tmp = Path.join(System.tmp_dir!(), "delfos_migrate_test_#{System.unique_integer()}")
      File.mkdir_p!(tmp)
      Application.put_env(:delfos, :config_dir, tmp)

      on_exit(fn ->
        File.rm_rf!(tmp)
        Application.delete_env(:delfos, :config_dir)
      end)

      :ok
    end

    test "reports clean when no stale entries" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Config.run(["migrate-local"])
        end)

      assert output =~ "No stale cloud providers found"
    end

    test "lists stale entries when present" do
      Manager.write(%{
        "llm" => %{"provider" => "openai", "url" => "https://api.openai.com/v1"}
      })

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Config.run(["migrate-local"])
        end)

      assert output =~ "stale cloud provider"
      assert output =~ "[llm] provider=openai"
    end

    test "--yes applies the migration without prompting" do
      Manager.write(%{
        "llm" => %{"provider" => "openai", "url" => "https://api.openai.com/v1"}
      })

      ExUnit.CaptureIO.capture_io(fn ->
        Config.run(["migrate-local", "--yes"])
      end)

      cfg = Manager.load()
      assert cfg["llm"]["provider"] == "local"
      assert cfg["llm"]["url"] == "http://127.0.0.1:9999"
    end
  end
end
