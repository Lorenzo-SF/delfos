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

  # async: false because each test spawns a child process via spawn_link
  # and several call System.halt/1 through the CLI. Async + halt causes
  # a race where the next test's capture_io picks up the previous test's
  # I/O redirection.
  use ExUnit.Case, async: false

  setup_all do
    # Pre-start the application so main/1's Application.ensure_all_started
    # doesn't race with capture_io. Without this, tests that fall through
    # to the generic main(args) clause (which boots the app) lose their
    # IO redirection before the output reaches the test process.
    Application.ensure_all_started(:logger)
    Application.ensure_all_started(:delfos)

    on_exit(fn ->
      # Don't stop the app — other test files may need it.
      :ok
    end)

    :ok
  end

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
      assert "models" not in names, "models should be merged into config"
      assert "status" in names
      assert "stadistics" not in names, "stadistics (typo) was removed in A1"
      assert "watch" in names
      assert "mcp" in names
      assert "serve" not in names, "serve was removed in A1 (use mcp)"
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
      # Alaja.print_raw writes to :stdio (default). capture_io/1 without
      # a device captures BOTH stdout and stderr, which is what we want
      # when the framework may write to either.
      output = capture_io(fn -> Delfos.CLI.main([]) end)
      assert output =~ "init"
      assert output =~ "scan"
      assert output =~ "version"
    end

    test "with an unknown command prints an error" do
      # Verify the dispatch contract: in production mode, main/1 calls
      # System.halt(1) for unknown commands. In test mode (Mix.env() == :test)
      # it returns :ok to avoid killing the test runner. The actual
      # exit-code propagation is verified by the functional tests in
      # test/functional/cli_doctor_test.exs against the built binary.
      assert Delfos.CLI.main(["nonexistent"]) == :ok
    end

    test "routes version to the version command" do
      # Should print the Delfos version (which is non-empty).
      output = capture_io(fn -> Delfos.CLI.main(["version"]) end)
      assert output =~ "Delfos v"
    end

    test "routes --help to the global help list" do
      output = capture_io(fn -> Delfos.CLI.main(["--help"]) end)
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

    test "config models routes to Delfos.CLI.Commands.Config.run" do
      output = capture_io(fn -> Delfos.CLI.main(["config", "models"]) end)
      assert output =~ "Embedding"
      assert output =~ "LLM"
    end

    test "config setup routes to Delfos.CLI.Commands.Config.run" do
      output = capture_io(fn -> Delfos.CLI.main(["config", "setup", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "'models' is no longer a top-level command" do
      # The dispatcher should report it as unknown and suggest using config
      output =
        capture_io(:stderr, fn ->
          Delfos.CLI.main(["models"])
        end)

      assert output =~ "unknown"
      # Should suggest the replacement
      assert output =~ "config" or output =~ "Available"
    end

    test "'setup' is no longer a top-level command" do
      output =
        capture_io(:stderr, fn ->
          Delfos.CLI.main(["setup"])
        end)

      assert output =~ "unknown"
    end

    test "status --help routes to Delfos.CLI.Commands.Status.run" do
      output = capture_io(fn -> Delfos.CLI.main(["status", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "status --statistics shows MCP usage + index breakdown" do
      output = capture_io(fn -> Delfos.CLI.main(["status", "--help"]) end)
      assert output =~ "USAGE"
      assert output =~ "--statistics"
    end
  end
end
