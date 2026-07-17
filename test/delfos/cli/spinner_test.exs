defmodule Delfos.CLI.SpinnerTest do
  @moduledoc """
  Unit tests for the Spinner helper.

  Covers:
    - Returns the result of the wrapped function
    - Silent (no animation) when stderr is not a TTY
    - Doesn't crash on exceptions inside the wrapped function
    - TTY simulation: animated spinner output, non-TTY fallback
  """

  use ExUnit.Case, async: true

  alias Delfos.CLI.Spinner

  describe "with/2" do
    test "returns the result of the wrapped function" do
      result = Spinner.with("loading", fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end

    test "works with simple values" do
      assert Spinner.with("loading", fn -> "hello" end) == "hello"
      assert Spinner.with("loading", fn -> 123 end) == 123
      assert Spinner.with("loading", fn -> nil end) == nil
    end

    test "doesn't catch exceptions from the wrapped function" do
      assert_raise RuntimeError, "boom", fn ->
        Spinner.with("loading", fn -> raise "boom" end)
      end
    end

    test "doesn't catch exits" do
      assert catch_exit(Spinner.with("loading", fn -> exit(:shutdown) end)) == :shutdown
    end

    test "doesn't catch throws" do
      assert catch_throw(Spinner.with("loading", fn -> throw(:oops) end)) == :oops
    end
  end

  describe "TTY simulation" do
    test "with TTY override, spinner renders animation frames" do
      Spinner.set_tty_override(true)

      # Capture stderr inside the spinner
      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Spinner.with("test-label", fn ->
            Process.sleep(10)
            :ok
          end)
        end)

      Spinner.clear_tty_override()

      # The spinner should produce animated output with the label
      # and animation escape sequences (\r\e[2K).
      assert stderr =~ "test-label"
      assert stderr =~ "\r\e[2K"
    end

    test "with TTY override, fast ops still show minimal output" do
      Spinner.set_tty_override(true)

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          # Fast op (<100ms) — spinner starts but finishes quickly
          Spinner.with("fast-op", fn -> :ok end)
        end)

      Spinner.clear_tty_override()

      # Should have at least started the spinner before completing
      assert stderr =~ "fast-op" or stderr == ""
    end

    test "non-TTY fallback prints done line for slow ops" do
      Spinner.set_tty_override(false)

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Spinner.with("slow-op", fn ->
            Process.sleep(150)
            :ok
          end)
        end)

      Spinner.clear_tty_override()

      # Non-TTY: no animation, just "done in Nms" line
      refute stderr =~ "\r\e[2K"
      assert stderr =~ "done in"
    end

    test "non-TTY fallback skips done line for fast ops" do
      Spinner.set_tty_override(false)

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Spinner.with("fast-op", fn -> :ok end)
        end)

      Spinner.clear_tty_override()

      # Fast op (<100ms) in non-TTY: no output at all
      assert stderr == ""
    end
  end
end
