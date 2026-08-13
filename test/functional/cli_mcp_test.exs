defmodule Delfos.Functional.CLIMCPTest do
  @moduledoc """
  Functional tests for the `delfos mcp` command.

  The MCP server is a long-running process that reads JSON-RPC from
  stdin and writes responses to stdout. Whether the server actually
  starts depends on the environment:

    * With working LLM endpoints — the server boots, responds to an
      `initialize` request with a JSON-RPC response, and is then killed.
    * Without LLM endpoints — the LLMGuard (`:required`) aborts with a
      clear message before the server reads stdin.

  The initialize test below is adaptive: it runs the real stdio flow
  when endpoints are reachable, and otherwise verifies the guard
  contract (non-zero exit + clear LLM message), mirroring
  `cli_init_test.exs`. The `--version` test always runs.
  """

  use ExUnit.Case, async: false

  @moduletag :functional
  @moduletag :slow
  @moduletag :cli

  alias Candil.Health
  alias Delfos.Config.Manager

  setup do
    binary =
      System.find_executable("delfos") ||
        Path.expand("delfos", File.cwd!()) ||
        raise "delfos binary not found — run `mix gen` first"

    %{binary: binary}
  end

  test "mcp starts and responds to JSON-RPC initialize (or guard contract without LLM)",
       %{binary: binary} do
    if llm_available?() do
      init_request = ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})

      port =
        Port.open({:spawn_executable, binary},
          [:binary, :exit_status, args: ["mcp"]]
        )

      Port.command(port, init_request <> "\n")
      response = collect_port_output(port, 8_000)
      Port.close(port)

      assert response =~ "jsonrpc" or response =~ "serverInfo" or response =~ "capabilities",
             "expected JSON-RPC response, got: #{inspect(response)}"
    else
      # Guard contract: the binary must exit non-zero with a clear
      # LLM message, never crash with a stack trace.
      {output, exit_code} = run(binary, ["mcp"])

      assert exit_code != 0, "expected non-zero exit, got #{exit_code}: #{output}"
      assert output =~ "LLM", "expected LLM guard message, got: #{output}"
      refute output =~ "** (", "mcp crashed with an unhandled exception: #{output}"
    end
  end

  test "mcp with --version exits 0", %{binary: binary} do
    {output, exit_code} = run(binary, ["--version"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ "Delfos v"
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end

  defp llm_available? do
    urls = [Manager.embedding()[:url], Manager.llm()[:url]] |> Enum.reject(&is_nil/1)

    urls != [] and
      Enum.all?(urls, fn url ->
        case Health.probe(url, timeout: 500) do
          %{reachable: true} -> true
          _ -> false
        end
      end)
  end

  defp collect_port_output(port, timeout_ms) do
    receive_loop(port, "", timeout_ms)
  end

  defp receive_loop(port, acc, timeout_ms) do
    receive do
      {^port, {:data, data}} ->
        receive_loop(port, acc <> data, timeout_ms)

      {^port, {:exit_status, _status}} ->
        acc
    after
      timeout_ms ->
        acc
    end
  end
end
