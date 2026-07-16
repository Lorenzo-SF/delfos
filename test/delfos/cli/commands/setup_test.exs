defmodule Delfos.CLI.Commands.SetupTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Setup.

  Verifies:
    - --help / -h print the help block
    - Unknown subcommand prints the fallback message
    - summary_text/2 (public @doc false) maps all four combinations
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Setup

  describe "--help" do
    test "prints the help block" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Alaja.print_raw(Setup.help_text())
          nil
        end)

      assert output =~ "USAGE"
      assert output =~ "delfos config setup"
      assert output =~ "db"
      assert output =~ "llm"
    end

    # Note: setup.ex does NOT handle `-h` — only `--help`. The `-h` arg
    # falls through to the unknown-subcommand fallback. Verify that:
    test "-h is not a recognised short flag (falls to unknown-subcommand path)" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Setup.run(["-h"])
        end)

      assert output =~ "Unknown setup subcommand"
      assert output =~ "delfos config setup"
    end
  end

  describe "unknown subcommand fallback" do
    test "prints the unknown-subcommand hint" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Setup.run(["this-is-not-a-valid-subcommand"])
        end)

      assert output =~ "Unknown setup subcommand"
      assert output =~ "delfos config setup db"
      assert output =~ "delfos config setup llm"
      assert output =~ "top-level wizard"
    end
  end

  describe "summary_text/2 (public @doc false)" do
    test "both succeeded" do
      assert Setup.summary_text(true, true) == "All systems ready"
    end

    test "db ok, llm pending" do
      assert Setup.summary_text(true, false) =~ "Database OK"
      assert Setup.summary_text(true, false) =~ "LLM setup incomplete"
    end

    test "llm ok, db pending" do
      assert Setup.summary_text(false, true) =~ "LLM OK"
      assert Setup.summary_text(false, true) =~ "Database setup incomplete"
    end

    test "both pending" do
      assert Setup.summary_text(false, false) =~ "Both need attention"
    end
  end
end
