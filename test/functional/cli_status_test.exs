defmodule Delfos.Functional.CLIStatusTest do
  @moduledoc """
  Functional tests for the `delfos status` command.

  Exercises the real binary end-to-end. No mocks. Verifies exit
  codes and output for the indexed-projects / no-projects paths.
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

  test "status exits 0 and shows 'Indexed projects:' or 'no projects' guidance", %{binary: binary} do
    {output, exit_code} = run(binary, ["status"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    # Either shows indexed count, or a guidance message when empty
    assert output =~ "Indexed projects:" or output =~ "none"
  end

  test "status with --help exits 0 and shows flag documentation", %{binary: binary} do
    {output, exit_code} = run(binary, ["status", "--help"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ "USAGE" or output =~ "usage"
    assert output =~ "status"
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end
end
