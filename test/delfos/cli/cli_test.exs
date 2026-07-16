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

  # v2.6.0: handlers raise Delfos.CLI.Abort instead of calling
  # System.halt/1 directly. The top-level dispatcher propagates the
  # exception (it doesn't halt — the eScript entry point handles
  # exit codes via the raise). Tests that call `Delfos.CLI.main/1`
  # and DON'T expect an abort wrap the call in this helper so
  # ExUnit doesn't see the propagation. Tests that DO expect an
  # abort call Delfos.CLI.main/1 directly inside assert_raise.
  defp run_main(args) do
    Delfos.CLI.main(args)
  rescue
    e in Delfos.CLI.Abort -> {:abort, e.code}
  end

  # Final command list after Fase A cleanup. Removed deprecation aliases
  # (watch, serve, context, preset top-level, setup top-level, models
  # top-level) and the typo'd stadistics command (merged into
  # status --stats in a later phase). See docs/REFACTOR_PLAN.md §6.1.
  @expected_commands ~w(
    init scan query audit summarize explain graph agents config
    integrate doctor status mcp version
  )

  describe "__commands__/0" do
    test "lists every registered command" do
      names = Delfos.CLI.__commands__() |> Enum.map(& &1.name) |> Enum.sort()

      for expected <- @expected_commands do
        assert expected in names, "missing command #{expected}"
      end

      # Deprecated aliases that should NOT exist anymore
      for removed <- ~w(watch serve context preset setup models stadistics) do
        refute removed in names, "removed command #{removed} still registered"
      end
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
      # show_general_help/0 emits the Alaja table on stdout; capture both.
      output = capture_io(fn -> run_main([]) end)
      assert output =~ "init"
      assert output =~ "scan"
      assert output =~ "version"
    end

    test "with an unknown command prints an error" do
      # Alaja's error handler prints to stderr; capture it.
      stderr =
        capture_io(:stderr, fn ->
          assert_raise Delfos.CLI.Abort, fn ->
            Delfos.CLI.main(["nonexistent"])
          end
        end)

      assert stderr =~ "unknown"
    end

    test "routes version to the version command" do
      # Should print the Delfos version (which is non-empty).
      output = capture_io(fn -> run_main(["version"]) end)
      assert output =~ "Delfos v"
    end

    test "routes --help to the global help list" do
      output =
        capture_io(fn ->
          capture_io(:stderr, fn -> run_main(["--help"]) end)
        end)

      assert output =~ "init"
      assert output =~ "scan"
      assert output =~ "GLOBAL FLAGS"
    end

    test "routes -h to the global help list" do
      output =
        capture_io(fn ->
          capture_io(:stderr, fn -> run_main(["-h"]) end)
        end)

      assert output =~ "init"
      assert output =~ "GLOBAL FLAGS"
    end

    test "routes --version to version output" do
      output = capture_io(fn -> run_main(["--version"]) end)
      assert output =~ "Delfos v"
    end

    test "routes -v to version output" do
      output = capture_io(fn -> run_main(["-v"]) end)
      assert output =~ "Delfos v"
    end

    test "init --help routes to Delfos.CLI.Commands.Init.run" do
      output = capture_io(fn -> run_main(["init", "--help"]) end)
      assert output =~ "USAGE"
      assert output =~ "delfos init"
    end

    test "scan --help routes to Delfos.CLI.Commands.Scan.run" do
      output = capture_io(fn -> run_main(["scan", "--help"]) end)
      assert output =~ "USAGE"
      assert output =~ "delfos scan"
    end

    test "audit --help routes to Delfos.CLI.Commands.Audit.run" do
      output = capture_io(fn -> run_main(["audit", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "summarize --help routes to Delfos.CLI.Commands.Summarize.run" do
      output = capture_io(fn -> run_main(["summarize", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "explain --help routes to Delfos.CLI.Commands.Explain.run" do
      output = capture_io(fn -> run_main(["explain", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "graph --help routes to Delfos.CLI.Commands.Graph.run" do
      output = capture_io(fn -> run_main(["graph", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "agents --help routes to Delfos.CLI.Commands.Agents.run" do
      output = capture_io(fn -> run_main(["agents", "--help"]) end)
      assert output =~ "USAGE"
      assert output =~ "delfos agents"
    end

    test "config --help routes to Delfos.CLI.Commands.Config.run" do
      output = capture_io(fn -> run_main(["config", "--help"]) end)
      assert output =~ "config"
      assert output =~ "show"
    end

    test "integrate --help routes to Delfos.CLI.Commands.Integrate.run" do
      output = capture_io(fn -> run_main(["integrate", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "doctor --help routes to Delfos.CLI.Commands.Doctor.run" do
      output = capture_io(fn -> run_main(["doctor", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "config models routes to Delfos.CLI.Commands.Config.run" do
      output = capture_io(fn -> run_main(["config", "models"]) end)
      assert output =~ "Embedding"
      assert output =~ "LLM"
    end

    test "config setup routes to Delfos.CLI.Commands.Config.run" do
      output = capture_io(fn -> run_main(["config", "setup", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "status --help routes to Delfos.CLI.Commands.Status.run" do
      output = capture_io(fn -> run_main(["status", "--help"]) end)
      assert output =~ "USAGE"
    end

    test "deprecated aliases report as unknown commands" do
      for alias_name <- ~w(watch serve context preset setup models stadistics) do
        output =
          capture_io(:stderr, fn ->
            run_main([alias_name])
          end)

        assert output =~ "unknown",
               "expected `delfos #{alias_name}` to be reported as unknown"
      end
    end
  end
end
