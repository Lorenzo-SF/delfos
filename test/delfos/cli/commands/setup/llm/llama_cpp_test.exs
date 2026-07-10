defmodule Delfos.CLI.Commands.Setup.LLM.LlamaCppTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Setup.LLM.LlamaCpp

  setup do
    tmp =
      Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_llamacpp_test")

    File.mkdir_p!(tmp)
    Application.put_env(:delfos, :config_dir, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:delfos, :config_dir)
    end)

    :ok
  end

  describe "scan_ggufs/1" do
    test "returns an empty list for a directory with no .gguf files" do
      dir = Path.join(System.tmp_dir!(), "delfos_llamacpp_empty_#{System.unique_integer()}")
      File.mkdir_p!(dir)
      assert LlamaCpp.scan_ggufs(dir) == []
    end

    test "returns an empty list for a non-existent directory" do
      assert LlamaCpp.scan_ggufs("/nonexistent/abc/xyz") == []
    end

    test "returns sorted maps for local .gguf files" do
      dir = Path.join(System.tmp_dir!(), "delfos_llamacpp_gguf_#{System.unique_integer()}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "zeta.gguf"), "")
      File.write!(Path.join(dir, "alpha.gguf"), "")
      File.write!(Path.join(dir, "readme.txt"), "")

      result = LlamaCpp.scan_ggufs(dir)

      assert Enum.map(result, & &1.filename) == ["alpha.gguf", "zeta.gguf"]
      assert Enum.all?(result, &String.ends_with?(&1.filename, ".gguf"))
    end
  end
end
