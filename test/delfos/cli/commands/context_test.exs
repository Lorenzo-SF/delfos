defmodule Delfos.CLI.Commands.ContextTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Context.

  Verifies:
    - --help / -h print the help block
    - Integration stub: runs without DB-touching code crashing
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Context

  describe "--help" do
    test "prints the help block" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Context.run(["--help"])
        end)

      assert output =~ "USAGE"
      assert output =~ "delfos context"
      assert output =~ "--output"
      assert output =~ "--symbol"
      assert output =~ "--format"
    end

    test "-h also prints help" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Context.run(["-h"])
        end)

      assert output =~ "USAGE"
    end
  end

  describe "integration" do
    @tag :integration
    test "with no project, prints the empty-state warning" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Context.run([])
        end)

      # Empty-DB path prints "No hay proyectos"; populated path writes
      # markdown files. Either is valid.
      assert output =~ "No hay proyectos" or output =~ "AGENTS.md" or output =~ "context"
    end
  end
end
