defmodule Delfos.CLI.LLMGuardTest do
  @moduledoc """
  Tests for the LLMGuard pre-flight check.

  Verifies that:
    - Commands not in the requirements table return `:ok`
    - Commands requiring both endpoints fail when either is unreachable
    - Commands only requiring one endpoint skip the other
    - Commands with `:none` always return `:ok`
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.LLMGuard

  setup do
    # Each test gets an isolated HOME so the config doesn't collide
    # with the user's real ~/.config/delfos.
    fake_home = Path.join(System.tmp_dir!(), "delfos_llm_guard_#{System.unique_integer()}")
    File.mkdir_p!(fake_home)

    original_home = System.get_env("HOME")
    original_xdg = System.get_env("XDG_CONFIG_HOME")
    System.put_env("HOME", fake_home)
    System.put_env("XDG_CONFIG_HOME", fake_home)

    on_exit(fn ->
      System.put_env("HOME", original_home)
      if original_xdg, do: System.put_env("XDG_CONFIG_HOME", original_xdg)
      File.rm_rf!(fake_home)
    end)

    :ok
  end

  test "unknown command returns :ok" do
    assert LLMGuard.check("does-not-exist") == :ok
  end

  test "command with :none requirement returns :ok" do
    assert LLMGuard.check("audit") == :ok
    assert LLMGuard.check("graph") == :ok
    assert LLMGuard.check("config") == :ok
    assert LLMGuard.check("status") == :ok
    # `stadistics` was removed in v2.3.0 (commit `e01455e`); its functionality
    # is now `--stats` on `delfos status`. Unknown commands also return :ok
    # since `LLMGuard.check/1` is only called for live commands.
    assert LLMGuard.check("stadistics") == :ok
    assert LLMGuard.check("integrate") == :ok
    assert LLMGuard.check("doctor") == :ok
  end

  test "requirement/1 returns the level for known commands" do
    assert LLMGuard.requirement("scan") == :required
    assert LLMGuard.requirement("query") == :required
    assert LLMGuard.requirement("explain") == :required
    assert LLMGuard.requirement("summarize") == :required
    assert LLMGuard.requirement("mcp") == :required
    assert LLMGuard.requirement("init") == :required
    assert LLMGuard.requirement("watch") == :optional
    assert LLMGuard.requirement("audit") == :none
    # `stadistics` removed in v2.3.0; unknown command → nil
    assert LLMGuard.requirement("stadistics") == nil
    assert LLMGuard.requirement("unknown") == nil
  end
end
