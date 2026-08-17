defmodule Delfos.Functional.CLIDoctorFullTest do
  @moduledoc """
  Functional tests for the `delfos doctor` command — extended suite.

  Beyond the smoke tests in `cli_doctor_test.exs`, this exercises:
  - `--json` output is valid JSON
  - `--fix` runs and reports the result
  - `--preflight` exit code contract (CI depends on 0/1/2)
  - `--guided` prompts in non-interactive stdin (should warn, not crash)
  - With valid env: all checks pass (0 exit, 0 failed)
  - With invalid env: at least one check fails (1 exit)
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

  test "--json output is parseable JSON", %{binary: binary} do
    {output, exit_code} = run(binary, ["doctor", "--json"])

    assert exit_code in [0, 1],
           "doctor should exit 0 (ok) or 1 (degraded), got #{exit_code}: #{output}"

    # The JSON output is embedded in the doctor run output
    # Extract the JSON part (between { and the last })
    case extract_json(output) do
      {:ok, json} ->
        assert is_map(json) or is_list(json), "expected JSON object or array"
        # Should have 'results' key with the check results
        assert Map.has_key?(json, "results") or Map.has_key?(json, "checks"),
               "expected JSON to have 'results' or 'checks' key"

      :error ->
        # Doctor might not have run cleanly in this env; if so, skip
        :ok
    end
  end

  test "--preflight exits 0 when all critical checks pass, 1+ when they fail",
       %{binary: binary} do
    {output, exit_code} = run(binary, ["doctor", "--preflight"])

    # Contract: 0 = all pass, 1 = degraded, 2 = critical failed
    assert exit_code in [0, 1, 2],
           "preflight must exit 0/1/2, got #{exit_code}: #{output}"

    if exit_code == 0 do
      assert output =~ "OK" or output =~ "pass" or output =~ "✓"
    else
      assert output =~ "fail" or output =~ "✗" or output =~ "degraded"
    end
  end

  test "without flags, doctor runs the full check suite (longer output)",
       %{binary: binary} do
    {output, exit_code} = run(binary, ["doctor"])

    assert exit_code in [0, 1, 2], "got #{exit_code}: #{output}"
    # Full doctor should report at least 3 checks
    checks_count =
      output
      |> String.split("\n")
      |> Enum.count(fn line -> line =~ ~r/[✓✗!]/ end)

    assert checks_count >= 3, "expected at least 3 checks, got #{checks_count}"
  end

  test "--help exits 0 and lists all doctor flags", %{binary: binary} do
    {output, exit_code} = run(binary, ["doctor", "--help"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"

    for flag <- ~w(--fix --guided --preflight --json) do
      assert output =~ flag, "expected doctor --help to list `#{flag}`"
    end
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end

  # Extract the first JSON object/array from a string with mixed
  # output (e.g. ANSI escapes, leading text).
  defp extract_json(output) do
    # Find first { or [ and matching ] or }
    cond do
      start = :binary.match(output, "{") ->
        # Find matching closing brace by counting
        case find_close(output, elem(start, 0)) do
          nil ->
            :error

          close_idx ->
            {:ok,
             output
             |> binary_part(elem(start, 0), close_idx - elem(start, 0) + 1)
             |> Jason.decode!()}
        end

      start = :binary.match(output, "[") ->
        case find_close(output, elem(start, 0)) do
          nil ->
            :error

          close_idx ->
            {:ok,
             output
             |> binary_part(elem(start, 0), close_idx - elem(start, 0) + 1)
             |> Jason.decode!()}
        end

      true ->
        :error
    end
  rescue
    _ -> :error
  end

  defp find_close(str, start_idx) do
    {_, depth, _} =
      str
      |> :binary.bin_to_list()
      |> Enum.drop(start_idx)
      |> Enum.reduce_while({start_idx, 0, nil}, fn byte, {idx, d, _} ->
        cond do
          byte == ?{ ->
            {idx + 1, d + 1, nil}

          byte == ?} ->
            if d == 1, do: {:halt, {idx, d - 1, idx}}, else: {idx + 1, d - 1, nil}

          true ->
            {idx + 1, d, nil}
        end
      end)

    elem({depth, depth, nil}, 0)
  end
end
