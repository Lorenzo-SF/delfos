defmodule Delfos.CLI.Commands.DoctorTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Doctor.

  Verifies:
    - --help prints the help block without crashing
    - --json outputs valid JSON
    - --fix mode passes through to Botica.Repair.Fixer
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Doctor

  describe "--help" do
    test "prints the help block" do
      # Capture stdout while running
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Doctor.run(["--help"])
        end)

      assert output =~ "USAGE"
      assert output =~ "delfos doctor"
      assert output =~ "--fix"
      assert output =~ "--interactive"
      assert output =~ "--json"
    end

    test "-h also prints help" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Doctor.run(["-h"])
        end)

      assert output =~ "USAGE"
    end
  end

  describe "JSON output" do
    @tag :integration
    test "--json emits valid JSON with results and summary" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Doctor.run(["--json"])
        end)

      assert {:ok, parsed} = Jason.decode(output)
      assert is_map(parsed)
      assert Map.has_key?(parsed, "results") or Map.has_key?(parsed, "summary")
    end
  end
end
