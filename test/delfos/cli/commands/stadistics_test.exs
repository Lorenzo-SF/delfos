defmodule Delfos.CLI.Commands.StadisticsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Delfos.CLI.Commands.Stadistics

  describe "help" do
    test "no arguments shows help" do
      output = capture_io(fn -> assert :ok = Stadistics.run([]) end)

      assert output =~ "USAGE"
      assert output =~ "delfos stadistics <project_name>"
      assert output =~ "--list"
      assert output =~ "--all"
      assert output =~ "local database"
    end

    test "--help and -h show help" do
      for flag <- ["--help", "-h"] do
        output = capture_io(fn -> assert :ok = Stadistics.run([flag]) end)
        assert output =~ "METRIC DEFINITIONS"
      end
    end
  end

  describe "argument validation" do
    test "rejects --list with --all" do
      output =
        capture_io(fn ->
          assert {:error, :invalid_arguments} =
                   Stadistics.run_with_opts(%{project: "", list: true, all: true})
        end)

      assert output =~ "cannot be used together"
    end

    test "rejects a project combined with a selection flag" do
      output =
        capture_io(fn ->
          assert {:error, :invalid_arguments} =
                   Stadistics.run_with_opts(%{project: "delfos", list: true, all: false})
        end)

      assert output =~ "cannot be combined"
    end

    test "rejects more than one positional project name" do
      output =
        capture_io(fn ->
          assert {:error, :invalid_arguments} = Stadistics.run(["one", "two"])
        end)

      assert output =~ "Only one project name"
    end
  end
end
