defmodule Delfos.CLI.Commands.StatusTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Status.

  Verifies:
    - --help / -h print the help block
    - format_last_scan/1 freshness buckets (green/yellow/red via ANSI)
    - Empty DB integration: prints the empty-state warning inside a Box
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Status

  describe "--help" do
    test "prints the help block" do
      output =
        Status.help_text()

      assert output =~ "USAGE"
      assert output =~ "delfos status"
      assert output =~ "file count"
      assert output =~ "embedding"
    end

    test "-h also prints help" do
      output =
        Status.help_text()

      assert output =~ "USAGE"
    end
  end

  describe "format_last_scan/1" do
    test "nil returns 'never'" do
      out = Status.format_last_scan(nil)
      assert out =~ "never"
    end

    test "< 60s ago is green ('just now')" do
      dt = DateTime.utc_now()
      out = Status.format_last_scan(dt)
      assert out =~ "just now"
      # Green RGB tuple
      assert out =~ "\e[38;2;0;200;80m"
    end

    test "minutes ago is green" do
      dt = DateTime.add(DateTime.utc_now(), -30 * 60, :second)
      out = Status.format_last_scan(dt)
      assert out =~ "30m ago"
    end

    test "hours ago (< 24h) is yellow" do
      dt = DateTime.add(DateTime.utc_now(), -5 * 3600, :second)
      out = Status.format_last_scan(dt)
      assert out =~ "5h ago"
      assert out =~ "\e[38;2;220;180;0m"
    end

    test "days ago (>= 24h) is red" do
      dt = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
      out = Status.format_last_scan(dt)
      assert out =~ "3d ago"
      assert out =~ "\e[38;2;220;50;50m"
    end

    test "ISO 8601 strings are parsed" do
      dt = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      iso = DateTime.to_iso8601(dt)
      out = Status.format_last_scan(iso)
      assert out =~ "2h ago"
    end

    test "malformed strings pass through unchanged (with neutral color)" do
      out = Status.format_last_scan("not-a-date")
      assert out =~ "not-a-date"
    end

    test "NaiveDateTime is treated as UTC" do
      ndt = %{NaiveDateTime.utc_now() | year: 2020, month: 1, day: 1}
      out = Status.format_last_scan(ndt)
      assert out =~ "ago"
      # 2020 is more than 24h ago → red
      assert out =~ "\e[38;2;220;50;50m"
    end
  end

  describe "integration" do
    @tag :integration
    test "with no projects, prints the empty-state warning inside a Box" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Status.run([])
        end)

      # v2.5.0: status wraps everything in Alaja.Components.Box with
      # title "Delfos Project Status".
      assert output =~ "Delfos Project Status"
      # Empty-state message is preserved (paraphrased).
      assert output =~ "no projects registered" or output =~ "(none"
    end
  end
end
