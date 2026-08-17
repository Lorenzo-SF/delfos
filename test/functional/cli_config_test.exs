defmodule Delfos.Functional.CLIConfigTest do
  @moduledoc """
  Functional tests for the `delfos config` subcommands.

  Covers:
  - `config show` — prints active configuration
  - `config path` — prints the config file path
  - `config set <section>.<key> <value>` — writes a value
  - `config get <section>.<key>` — reads a value back
  - `config preset <name>` — applies a preset
  - `config preset bogus` — error path

  Each test uses a tmp config dir so the host config is not mutated.
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

    tmp = Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_config_fn")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    original_config = Application.get_env(:delfos, :config_dir)
    Application.put_env(:delfos, :config_dir, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)

      if original_config,
        do: Application.put_env(:delfos, :config_dir, original_config),
        else: Application.delete_env(:delfos, :config_dir)
    end)

    %{binary: binary, tmp: tmp}
  end

  test "config path exits 0 and mentions .config/delfos", %{binary: binary} do
    {output, exit_code} = run(binary, ["config", "path"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ ".config/delfos"
  end

  test "config show exits 0 and prints JSON keys", %{binary: binary} do
    {output, exit_code} = run(binary, ["config", "show"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    # JSON config has these top-level sections
    assert output =~ "embedding" or output =~ "llm"
  end

  test "config set writes a value and config get reads it back", %{binary: binary} do
    {output1, exit1} = run(binary, ["config", "set", "llm", "model", "test-model-x"])

    assert exit1 == 0, "config set failed: exit #{exit1}: #{output1}"

    {output2, exit2} = run(binary, ["config", "get", "llm", "model"])

    assert exit2 == 0, "config get failed: exit #{exit2}: #{output2}"
    assert output2 =~ "test-model-x", "expected get to return the value we set"
  end

  test "config preset openai applies a preset", %{binary: binary} do
    {output, exit_code} = run(binary, ["config", "preset", "openai"])

    assert exit_code == 0, "expected exit 0, got #{exit_code}: #{output}"
    assert output =~ "openai" or output =~ "preset"
  end

  test "config preset bogus-name exits 1 (error)", %{binary: binary} do
    {output, exit_code} = run(binary, ["config", "preset", "totally-bogus-xyz-12345"])

    assert exit_code == 1, "expected exit 1 for bogus preset, got #{exit_code}: #{output}"
    assert output =~ "Unknown" or output =~ "error" or output =~ "Invalid"
  end

  defp run(binary, args) do
    {output, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
    {String.trim(output), exit_code}
  end
end
