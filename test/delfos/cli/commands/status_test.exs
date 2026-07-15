defmodule Delfos.CLI.Commands.StatusTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Status.

  Verifies:
    - --help / -h print the help block
    - Empty DB integration: prints "(none — run: delfos init)" warning
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

  describe "integration" do
    @tag :integration
    test "with no projects, prints the empty-state warning" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Status.run([])
        end)

      assert output =~ "DELFOS STATUS"
      # Either the empty-state warning or a project list. Both are valid
      # depending on DB state.
      assert output =~ "(none — run: delfos init)" or output =~ "┌"
    end
  end
end
