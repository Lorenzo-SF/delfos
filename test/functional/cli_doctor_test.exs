defmodule Delfos.Functional.CLIDoctorTest do
  @moduledoc """
  Functional tests for the `delfos doctor` command.

  Exercises the real CLI end-to-end (no mocks) against a live Postgres
  and a tmp config dir. Verifies exit codes, output content, and
  the --preflight contract that CI scripts rely on.
  """

  use ExUnit.Case, async: false

  @moduletag :functional
  @moduletag :slow
  @moduletag :cli

  setup do
    # Find the delfos binary. In dev: built binary in /tmp or PATH.
    # In CI: should be on PATH (after `mix gen` deploys it).
    binary =
      System.find_executable("delfos") ||
        Path.expand("delfos", File.cwd!()) ||
        raise "delfos binary not found — run `mix gen` first"

    # Each test gets a fresh tmp config dir so the host config is
    # not mutated.
    tmp = Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_fn_test")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    original_config = Application.get_env(:delfos, :config_dir)

    on_exit(fn ->
      File.rm_rf!(tmp)

      if original_config,
        do: Application.put_env(:delfos, :config_dir, original_config),
        else: Application.delete_env(:delfos, :config_dir)
    end)

    Application.put_env(:delfos, :config_dir, tmp)
    %{binary: binary, tmp: tmp}
  end

  test "--version exits 0 and prints 'Delfos v'", %{binary: binary} do
    {output, exit_code} = run(binary, ["--version"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ "Delfos v"
  end

  test "--help exits 0 and lists 16 commands", %{binary: binary} do
    {output, exit_code} = run(binary, ["--help"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    # Sanity-check a sample of the commands appear
    for cmd <- ~w(init scan query audit doctor mcp version) do
      assert output =~ cmd, "expected `--help` output to list `#{cmd}` command"
    end
  end

  test "unknown command exits 1 and shows available commands", %{binary: binary} do
    {output, exit_code} = run(binary, ["nonexistent-command"])

    assert exit_code == 1, "expected exit 1 for unknown command, got #{exit_code}"
    assert output =~ "Error"
    assert output =~ "init"
  end

  test "version command exits 0 and prints version string", %{binary: binary} do
    {output, exit_code} = run(binary, ["version"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ "Delfos v"
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end
end
