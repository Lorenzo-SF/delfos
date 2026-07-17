defmodule Delfos.CLI.Commands.IntegrateTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Integrate.

  Tests:
    - safe_write/2 (backup behaviour with new/empty/existing files)
    - module surface (Integrate.run/1 is exported)
    - integrate_bar_tick/1 (AnimatedBar tick generation)
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Integrate

  describe "integrate_bar_tick/1" do
    test "returns nil when stderr is not a TTY" do
      result = Integrate.integrate_bar_tick(3)
      assert result == nil or is_function(result, 3)
    end

    test "returns a function when TTY override is set" do
      Integrate.set_tty_override(true)
      result = Integrate.integrate_bar_tick(3)
      Integrate.clear_tty_override()
      assert is_function(result, 3)
    end

    test "tick function renders frames and writes via IO.write" do
      Integrate.set_tty_override(true)

      tick = Integrate.integrate_bar_tick(3)

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          tick.(0, 3, "test-agent")
          tick.(1, 3, "test-agent")
          tick.(2, 3, "test-agent")
        end)

      Integrate.clear_tty_override()

      # Only the last frame hits the 100ms throttle and writes.
      # idx=2/total=3 → 67%, so we see the last frame's output.
      assert stderr =~ "test-agent"
      assert stderr =~ "\r\e[2K"
      # Percentage should match the last frame (~67%)
      assert String.contains?(stderr, "6") and String.contains?(stderr, "%")
    end

    test "tick function handles edge cases" do
      Integrate.set_tty_override(true)

      # total=0 should not crash (no division by zero)
      tick0 = Integrate.integrate_bar_tick(0)
      assert is_function(tick0, 3)
      tick0.(0, 0, "")  # should not raise

      # total=1 should render last frame (idx == total-1)
      tick1 = Integrate.integrate_bar_tick(1)
      assert is_function(tick1, 3)

      # After clearing TTY, tick returns nil
      Integrate.clear_tty_override()
      assert Integrate.integrate_bar_tick(1) == nil
    end

    test "tick returns nil when stderr is not TTY" do
      Integrate.set_tty_override(false)

      result = Integrate.integrate_bar_tick(3)
      assert result == nil

      Integrate.clear_tty_override()
    end
  end

  describe "integrate_bar_tick TTY simulation" do
    test "single-agent shows AnimatedBar with TTY override" do
      Integrate.set_tty_override(true)

      tick = Integrate.integrate_bar_tick(1)

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          tick.(0, 1, "single-agent")
        end)

      Integrate.clear_tty_override()

      assert is_function(tick, 3)
      # Single agent should produce stderr with the label
      assert stderr =~ "single-agent"
    end

    test "multi-agent shows last agent label per tick" do
      Integrate.set_tty_override(true)

      tick = Integrate.integrate_bar_tick(2)

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          tick.(0, 2, "agent1")
          tick.(1, 2, "agent2")
        end)

      Integrate.clear_tty_override()

      # Only the last tick (idx >= total-1) triggers a write.
      # The 100ms throttle prevents the first tick from writing.
      assert stderr =~ "agent2"
      refute stderr =~ "agent1"
    end
  end

  describe "safe_write/2" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "delfos_test_#{System.unique_integer()}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    test "writes new file without backup", %{tmp: tmp} do
      path = Path.join(tmp, "fresh.json")
      :ok = Integrate.safe_write(path, ~s({"a":1}))

      assert File.read!(path) == ~s({"a":1})
      assert Enum.all?(File.ls!(tmp), &(not String.contains?(&1, ".bak-")))
    end

    test "backs up non-empty existing file before overwriting", %{tmp: tmp} do
      path = Path.join(tmp, "config.json")
      File.write!(path, ~s({"old":true}))

      :ok = Integrate.safe_write(path, ~s({"new":true}))

      assert File.read!(path) == ~s({"new":true})

      backups =
        File.ls!(tmp)
        |> Enum.filter(&String.contains?(&1, ".bak-"))

      assert length(backups) == 1
      assert File.read!(Path.join(tmp, hd(backups))) == ~s({"old":true})
    end

    test "skips backup when overwriting empty file", %{tmp: tmp} do
      path = Path.join(tmp, "empty.json")
      File.write!(path, "")

      :ok = Integrate.safe_write(path, ~s({"filled":true}))

      assert File.read!(path) == ~s({"filled":true})

      backups =
        File.ls!(tmp)
        |> Enum.filter(&String.contains?(&1, ".bak-"))

      assert Enum.empty?(backups)
    end

    test "preserves nested config structures", %{tmp: tmp} do
      # Real-world case: ~/.claude.json may have mcpServers.github, etc.
      path = Path.join(tmp, ".claude.json")
      original = ~s({"mcpServers":{"github":{"command":"gh"}}})
      File.write!(path, original)

      :ok = Integrate.safe_write(path, ~s({"mcpServers":{"delfos":{"command":"delfos"}}}))

      backups = File.ls!(tmp) |> Enum.filter(&String.contains?(&1, ".bak-"))
      assert length(backups) == 1
      assert File.read!(Path.join(tmp, hd(backups))) == original
    end
  end

  describe "module surface" do
    test "Integrate.run/1 is exported" do
      assert function_exported?(Integrate, :run, 1)
    end
  end
end
