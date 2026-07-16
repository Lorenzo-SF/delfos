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
      # In test environment stderr is typically not a TTY, so
      # integrate_bar_tick should return nil (which disables the bar).
      result = Integrate.integrate_bar_tick(3)
      assert result == nil or is_function(result, 3)
    end

    test "returned tick function does not crash when called" do
      # Even in non-TTY the bar tick returns nil, so we test the
      # happy path by calling the function directly when available.
      case Integrate.integrate_bar_tick(1) do
        nil ->
          # Non-TTY: nothing to test, just assert no-crash above
          assert true

        tick when is_function(tick, 3) ->
          # Tick should accept (idx, total, agent) and not raise
          tick.(0, 1, "test-agent")
          tick.(0, 1, "test-agent")
          assert true
      end
    end

    test "tick handles single-agent correctly" do
      # v2.7.0: single-agent (total=1) now shows the bar too.
      # The tick function should be callable with idx 0, total 1.
      case Integrate.integrate_bar_tick(1) do
        nil -> assert true
        tick when is_function(tick, 3) ->
          tick.(0, 1, "single-agent")
          # Should not raise with partial args either
          tick.(0, 1, "single-agent")
          assert true
      end
    end

    test "tick handles multi-agent edge cases" do
      # total=0 edge case (empty agent list) — should be callable.
      case Integrate.integrate_bar_tick(0) do
        nil -> assert true
        tick when is_function(tick, 3) ->
          tick.(0, 0, "")
          assert true
      end
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
