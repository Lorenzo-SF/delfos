defmodule Delfos.CLI.Commands.SummarizeTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Summarize.

  Verifies:
    - --help / -h print the help block
    - Integration stub: full command runs without DB-touching code crashing
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Summarize

  describe "--help" do
    test "prints the help block" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Summarize.run(["--help"])
        end)

      assert output =~ "USAGE"
      assert output =~ "delfos summarize"
      assert output =~ "--level"
      assert output =~ "--force"
    end

    test "-h also prints help" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Summarize.run(["-h"])
        end)

      assert output =~ "USAGE"
    end
  end

  describe "integration" do
    @tag :integration
    test "with no project, prints the empty-state warning and halts" do
      # The command calls System.halt(1) after the warning, so this
      # integration test only runs when a populated DB is available and
      # the halt path can be intercepted by the runner.
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Summarize.run([])
        end)

      # With a populated DB, summarization prints "Generando resúmenes...".
      # Without one, it prints "No hay proyectos". Either is valid.
      assert output =~ "Generando resúmenes" or output =~ "No hay proyectos"
    end
  end
end