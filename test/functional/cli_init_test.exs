defmodule Delfos.Functional.CLIInitTest do
  @moduledoc """
  Functional tests for the `delfos init` command.

  Note: in the test env there is no working LLM endpoint, so the
  LLMGuard aborts most invocations before they reach the path-safety
  or scan steps. These tests verify the contract: the command exits
  non-zero with a clear LLM-related message when the guard fires,
  and exits 0 for help. The full init flow (project creation + scan
  + embeddings) requires a working LLM and is covered by integration
  tests in `mcp_init_test.exs`.
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

  test "--help exits 0 and shows USAGE", %{binary: binary} do
    {output, exit_code} = run(binary, ["init", "--help"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ "USAGE"
    assert output =~ "delfos init"
  end

  test "-h shows help (alias)", %{binary: binary} do
    {output, exit_code} = run(binary, ["init", "-h"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ "USAGE"
  end

  test "init with no args shows help or error gracefully (never crashes)",
       %{binary: binary} do
    {output, exit_code} = run(binary, ["init"])

    # Either 0 (help shown) or non-zero (LLM guard + missing path).
    # Either way: must not crash with a stack trace.
    refute output =~ "** (", "init crashed with an unhandled exception: #{output}"
    # If non-zero, must have a clear message
    if exit_code != 0 do
      assert output =~ "LLM" or output =~ "embed" or output =~ "endpoint" or
               output =~ "missing" or output =~ "Usage" or output =~ "usage"
    end
  end

  test "init on any path without LLM exits non-zero with LLM message",
       %{binary: binary} do
    # Any init invocation requires a working LLM. In the test env
    # there is no LLM, so the command should exit non-zero with a
    # clear "LLM unreachable" message — regardless of the path.
    # This verifies the LLMGuard integration, not the path logic.
    {output, exit_code} = run(binary, ["init", "/tmp"])

    assert exit_code != 0, "expected non-zero exit, got 0: #{output}"
    assert output =~ "LLM" or output =~ "embed" or output =~ "endpoint" or
             output =~ "unreachable" or output =~ "doctor"
  end

  test "init on a path with deny-list match still exits cleanly (not a crash)",
       %{binary: binary} do
    # ~/.ssh is in the deny-list. With no LLM, the LLMGuard fires
    # before the path check, so we can't test the deny-list directly
    # in this env. But the command should NEVER crash with an
    # unhandled exception, regardless of the path.
    ssh = Path.expand("~/.ssh")

    {output, exit_code} = run(binary, ["init", ssh])

    refute output =~ "** (", "init crashed with an unhandled exception: #{output}"
    # Exit code: 0 if SSH is in deny-list and was rejected before LLM
    # check (unlikely in current flow); non-zero if LLM guard fires
    # first or deny-list check fires. Both are acceptable.
    assert exit_code in [0, 1, 2, 78], "got #{exit_code}: #{output}"
  end

  test "init on a regular file (not a dir) doesn't crash", %{binary: binary} do
    file = "/tmp/delfos_test_regular_file_init.ex"
    File.write!(file, "defmodule X do end\n")
    on_exit(fn -> File.rm!(file) end)

    {output, exit_code} = run(binary, ["init", file])

    refute output =~ "** (", "init crashed: #{output}"
    assert exit_code in [0, 1, 2, 78], "got #{exit_code}: #{output}"
  end

  test "init on a non-existent path doesn't crash", %{binary: binary} do
    bogus = "/tmp/delfos_definitely_does_not_exist_#{System.unique_integer([:positive])}"

    {output, exit_code} = run(binary, ["init", bogus])

    refute output =~ "** (", "init crashed: #{output}"
    assert exit_code in [0, 1, 2, 78], "got #{exit_code}: #{output}"
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end
end
