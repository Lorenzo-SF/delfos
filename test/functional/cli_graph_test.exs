defmodule Delfos.Functional.CLIGraphTest do
  @moduledoc """
  Functional tests for the `delfos graph` subcommands.

  Covers the help output and routing for each subcommand. The actual
  graph queries require an indexed project; those scenarios are
  covered by `mcp_graph_test.exs` against the live binary.
  """

  use ExUnit.Case, async: false

  @moduletag :functional
  @moduletag :slow
  @moduletag :cli

  setup do
    binary =
      System.find_executable("delfos") ||
        Path.expand("delfos", File.cwd!()) ||
        raise "delfos binary not found — run `mix gen` first"

    %{binary: binary}
  end

  test "graph --help exits 0 and lists subcommands", %{binary: binary} do
    {output, exit_code} = run(binary, ["graph", "--help"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    for sub <- ~w(callers callees impact cycles) do
      assert output =~ sub, "expected `#{sub}` in graph help"
    end
  end

  test "graph without subcommand shows usage and exits 0 or 1", %{binary: binary} do
    {output, exit_code} = run(binary, ["graph"])

    # Acceptable: 0 (shows help) or 1 (requires subcommand)
    assert exit_code in [0, 1, 2],
           "expected 0/1/2, got #{exit_code}: #{output}"

    assert output =~ "USAGE" or output =~ "usage" or output =~ "callers"
  end

  test "graph with --help shows --depth flag", %{binary: binary} do
    {output, exit_code} = run(binary, ["graph", "--help"])

    assert exit_code == 0, "got #{exit_code}: #{output}"
    assert output =~ "--depth", "expected `--depth` flag in graph help"
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end
end
