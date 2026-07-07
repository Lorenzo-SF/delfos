defmodule Delfos.CLITest do
  @moduledoc """
  Tests for the migrated `Delfos.CLI` (DSL-based) module.

  These verify:
    1. `__commands__/0` returns the expected list of commands.
    2. `main/1` with no args shows the help text.
    3. `main/1` with an unknown command prints an error and the help text.
    4. `--help` on individual commands routes correctly to each command's
       `run(["--help"])`.
    5. The `version` command returns without error.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "__commands__/0" do
    test "lists every registered command" do
      commands = Delfos.CLI.__commands__()
      names = Enum.map(commands, & &1.name) |> Enum.sort()

      assert "init" in names
      assert "scan" in names
      assert "query" in names
      assert "audit" in names
      assert "summarize" in names
      assert "explain" in names
      assert "graph" in names
      assert "context" in names
      assert "config" in names
      assert "integrate" in names
      assert "doctor" in names
      assert "models" in names
      assert "status" in names
      assert "watch" in names
      assert "serve" in names
      assert "version" in names
    end

    test "every command has a description" do
      for cmd <- Delfos.CLI.__commands__() do
        assert is_binary(cmd.description) and cmd.description != "",
               "command #{cmd.name} must have a non-empty description"
      end
    end

    test "every command has a run handler" do
      for cmd <- Delfos.CLI.__commands__() do
        case cmd.run do
          {mod, fun} when is_atom(mod) and is_atom(fun) -> :ok
          _ -> flunk("command #{cmd.name} must have a {module, function} run handler")
        end
      end
    end
  end

  describe "main/1" do
    test "with no args shows the available commands list" do
      output = capture_io(:stderr, fn -> Delfos.CLI.main([]) end)
      assert output =~ "init"
      assert output =~ "scan"
      assert output =~ "version"
    end

    test "with an unknown command prints an error" do
      output = capture_io(:stderr, fn -> Delfos.CLI.main(["nonexistent"]) end)
      assert output =~ "unknown"
      assert output =~ "init"
    end

    test "routes version to the version command" do
      # Should print the Delfos version (which is non-empty).
      output = capture_io(fn -> Delfos.CLI.main(["version"]) end)
      assert output =~ "Delfos v"
    end

    test "routes --help to the global help list" do
      output =
        capture_io(fn ->
          capture_io(:stderr, fn -> Delfos.CLI.main(["--help"]) end)
        end)

      assert output =~ "init"
      assert output =~ "scan"
      assert output =~ "GLOBAL FLAGS"
    end

    test "routes -h to the global help list" do
      output =
        capture_io(fn ->
          capture_io(:stderr, fn -> Delfos.CLI.main(["-h"]) end)
        end)

      assert output =~ "init"
      assert output =~ "GLOBAL FLAGS"
    end

    test "routes --version to version output" do
      output = capture_io(fn -> Delfos.CLI.main(["--version"]) end)
      assert output =~ "Delfos v"
    end

    test "routes -v to version output" do
      output = capture_io(fn -> Delfos.CLI.main(["-v"]) end)
      assert output =~ "Delfos v"
    end

    test "init --help routes to Delfos.CLI.Commands.Init.run" do
      output = capture_io(fn -> Delfos.CLI.main(["init", "--help"]) end)
      assert output =~ "USAGE"
      assert output =~ "delfos init"
    end

    test "scan --help routes to Delfos.CLI.Commands.Scan.run" do
      output = capture_io(fn -> Delfos.CLI.main(["scan", "--help"]) end)
      assert output =~ "USAGE"
      assert output =~ "delfos scan"
    end

    test "audit --help routes to Delfos.CLI.Commands.Audit.run" do
      output = capture_io(fn -> Delfos.CLI.main(["audit", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "summarize --help routes to Delfos.CLI.Commands.Summarize.run" do
      output = capture_io(fn -> Delfos.CLI.main(["summarize", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "explain --help routes to Delfos.CLI.Commands.Explain.run" do
      output = capture_io(fn -> Delfos.CLI.main(["explain", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "graph --help routes to Delfos.CLI.Commands.Graph.run" do
      output = capture_io(fn -> Delfos.CLI.main(["graph", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "context --help routes to Delfos.CLI.Commands.Context.run" do
      output = capture_io(fn -> Delfos.CLI.main(["context", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "config --help routes to Delfos.CLI.Commands.Config.run" do
      output = capture_io(fn -> Delfos.CLI.main(["config", "--help"]) end)
      assert output =~ "config"
      assert output =~ "show"
    end

    test "integrate --help routes to Delfos.CLI.Commands.Integrate.run" do
      output = capture_io(fn -> Delfos.CLI.main(["integrate", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "doctor --help routes to Delfos.CLI.Commands.Doctor.run" do
      output = capture_io(fn -> Delfos.CLI.main(["doctor", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "models --help routes to Delfos.CLI.Commands.Models.run" do
      output = capture_io(fn -> Delfos.CLI.main(["models", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "status --help routes to Delfos.CLI.Commands.Status.run" do
      output = capture_io(fn -> Delfos.CLI.main(["status", "--help"]) end)
      assert output =~ "USAGE"
    end
  end
end
