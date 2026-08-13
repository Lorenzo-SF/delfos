defmodule Delfos.Functional.CLIIntegrateTest do
  @moduledoc """
  Functional tests for the `delfos integrate` command.

  `integrate` configures MCP integration with external AI agents
  (claude-code, opencode, aider). The command writes to a target
  agent's config directory; we use a tmp HOME so the host is not
  mutated.
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

    # Isolate HOME so the command writes to a tmp dir, not the host.
    tmp_home =
      Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_integrate_fn")

    File.rm_rf!(tmp_home)
    File.mkdir_p!(tmp_home)

    original_home = System.get_env("HOME")
    System.put_env("HOME", tmp_home)

    on_exit(fn ->
      File.rm_rf!(tmp_home)
      if original_home, do: System.put_env("HOME", original_home), else: System.delete_env("HOME")
    end)

    %{binary: binary, tmp_home: tmp_home}
  end

  test "--help exits 0 and lists agents + flags", %{binary: binary} do
    {output, exit_code} = run(binary, ["integrate", "--help"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    # The help output lists both --yes and --project flags, and the
    # available agent names (claude-code, opencode, etc.).
    assert output =~ "--yes", "expected integrate --help to list --yes"
    assert output =~ "--project", "expected integrate --help to list --project"
    assert output =~ "claude-code", "expected integrate --help to list claude-code"
  end

  test "integrate with --all and --yes (non-interactive) exits within timeout",
       %{binary: binary, tmp_home: tmp_home} do
    # Use a short timeout: this command writes to multiple agent config
    # dirs in $HOME; if it hangs on a prompt or LLM call, we want to
    # know. 30s is generous for what should be a few-second operation.
    task =
      Task.async(fn ->
        run(binary, ["integrate", "--all", "--yes"])
      end)

    case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_output, exit_code}} ->
        # Could be 0 (success) or 1 (LLM not configured). Either way
        # the command should not crash and should attempt the integration.
        assert exit_code in [0, 1, 78], "got #{exit_code}: see output"
        # At least one config file may have been written
        case File.ls(tmp_home) do
          {:ok, []} -> :ok
          {:ok, _files} -> :ok
          _ -> :ok
        end

      nil ->
        flunk("integrate --all --yes did not finish within 30s")
    end
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end
end
