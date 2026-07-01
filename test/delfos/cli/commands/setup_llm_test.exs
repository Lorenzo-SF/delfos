defmodule Delfos.CLI.Commands.Setup.LLMTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Setup.LLM.

  Verifies:
    - scan_ggufs/1 (public @doc false) returns the right shape for a directory
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Setup.LLM, as: SetupLLM

  describe "scan_ggufs/1" do
    setup do
      cwd = Path.join(System.tmp_dir!(), "delfos_setup_llm_test_#{:rand.uniform(99_999)}")
      File.mkdir_p!(cwd)
      on_exit(fn -> File.rm_rf!(cwd) end)
      %{cwd: cwd}
    end

    test "returns an empty list for a directory with no .gguf files", %{cwd: cwd} do
      assert SetupLLM.scan_ggufs(cwd) == []
    end

    test "returns an empty list for a non-existent directory" do
      assert SetupLLM.scan_ggufs("/nonexistent/path/abc/xyz") == []
    end

    test "returns a list of maps for .gguf files", %{cwd: cwd} do
      File.write!(Path.join(cwd, "model-1.gguf"), "")
      File.write!(Path.join(cwd, "model-2.gguf"), "")
      File.write!(Path.join(cwd, "readme.txt"), "not a gguf")

      result = SetupLLM.scan_ggufs(cwd)

      assert length(result) == 2

      Enum.each(result, fn entry ->
        assert is_map(entry)
        assert Map.has_key?(entry, :path)
        assert Map.has_key?(entry, :filename)
        assert String.ends_with?(entry.filename, ".gguf")
      end)

      filenames = Enum.map(result, & &1.filename) |> Enum.sort()
      assert filenames == ["model-1.gguf", "model-2.gguf"]
    end
  end
end
