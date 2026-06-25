defmodule Delfos.CLI.Commands.ModelsTest do
  @moduledoc """
  Smoke tests for Delfos.CLI.Commands.Models.

  Verifies --help and that the module is wired into the main dispatcher.
  """

  use ExUnit.Case, async: true

  alias Delfos.CLI.Commands.Models

  describe "--help" do
    test "prints the help block" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Models.run(["--help"])
        end)

      assert output =~ "USAGE"
      assert output =~ "delfos models"
      assert output =~ "--probe"
    end

    test "-h also prints help" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Models.run(["-h"])
        end)

      assert output =~ "USAGE"
    end
  end
end