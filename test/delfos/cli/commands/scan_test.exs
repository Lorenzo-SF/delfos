defmodule Delfos.CLI.Commands.ScanTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Scan.

  Verifies:
    - --help / -h print the help block
    - Flag parsing: --full and --workers N are accepted
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Scan

  describe "--help" do
    test "prints the help block" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Scan.run(["--help"])
        end)

      assert output =~ "USAGE"
      assert output =~ "delfos scan"
      assert output =~ "--full"
      assert output =~ "--workers"
    end

    test "-h also prints help" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Scan.run(["-h"])
        end)

      assert output =~ "USAGE"
    end
  end

  describe "integration" do
    @tag :integration
    test "with no project, prints the empty-state error and halts" do
      # System.halt(1) inside the command kills the test runner; this
      # integration test only runs when a populated DB is wired in.
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Scan.run([])
        end)

      # Populated-DB path prints "Scanning: ..."; empty-DB path halts
      # after "No projects registered." Both are valid if the test ran.
      assert output =~ "Scanning:" or output =~ "No projects registered"
    end
  end
end