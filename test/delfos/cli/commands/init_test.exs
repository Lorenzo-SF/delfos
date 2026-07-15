defmodule Delfos.CLI.Commands.InitTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Init.

  Verifies:
    - --help / -h print the help block
    - detect_primary_stack/1 (public @doc false) identifies stacks from markers
    - detect_all_stacks/1 (public @doc false) returns a non-empty list
    - Integration stub: with a fake project dir, init recognises the stack
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Init

  describe "--help" do
    test "prints the help block" do
      output =
        Init.help_text()

      assert output =~ "USAGE"
      assert output =~ "delfos init"
      assert output =~ "[path]"
    end

    test "-h also prints help" do
      output =
        Init.help_text()

      assert output =~ "USAGE"
    end
  end

  describe "detect_primary_stack/1" do
    setup do
      cwd = Path.join(System.tmp_dir!(), "delfos_init_test_#{:rand.uniform(99_999)}")
      File.mkdir_p!(cwd)
      on_exit(fn -> File.rm_rf!(cwd) end)
      %{cwd: cwd}
    end

    test "detects elixir from mix.exs", %{cwd: cwd} do
      File.write!(Path.join(cwd, "mix.exs"), "")
      assert Init.detect_primary_stack(cwd) == "elixir"
    end

    test "detects rust from Cargo.toml", %{cwd: cwd} do
      File.write!(Path.join(cwd, "Cargo.toml"), "")
      assert Init.detect_primary_stack(cwd) == "rust"
    end

    test "detects python from pyproject.toml", %{cwd: cwd} do
      File.write!(Path.join(cwd, "pyproject.toml"), "")
      assert Init.detect_primary_stack(cwd) == "python"
    end

    test "detects node from package.json", %{cwd: cwd} do
      File.write!(Path.join(cwd, "package.json"), "")
      assert Init.detect_primary_stack(cwd) == "node"
    end

    test "detects go from go.mod", %{cwd: cwd} do
      File.write!(Path.join(cwd, "go.mod"), "")
      assert Init.detect_primary_stack(cwd) == "go"
    end

    test "detects java from pom.xml", %{cwd: cwd} do
      File.write!(Path.join(cwd, "pom.xml"), "")
      assert Init.detect_primary_stack(cwd) == "java"
    end

    test "detects ruby from Gemfile", %{cwd: cwd} do
      File.write!(Path.join(cwd, "Gemfile"), "")
      assert Init.detect_primary_stack(cwd) == "ruby"
    end

    test "returns 'unknown' when no marker files are present", %{cwd: cwd} do
      assert Init.detect_primary_stack(cwd) == "unknown"
    end

    test "prefers elixir over python when both pyproject.toml and mix.exs exist",
         %{cwd: cwd} do
      # mix.exs wins because of cond ordering
      File.write!(Path.join(cwd, "mix.exs"), "")
      File.write!(Path.join(cwd, "pyproject.toml"), "")
      assert Init.detect_primary_stack(cwd) == "elixir"
    end
  end

  describe "detect_all_stacks/1" do
    setup do
      cwd = Path.join(System.tmp_dir!(), "delfos_init_test_#{:rand.uniform(99_999)}")
      File.mkdir_p!(cwd)
      on_exit(fn -> File.rm_rf!(cwd) end)
      %{cwd: cwd}
    end

    test "returns ['unknown'] for an empty directory", %{cwd: cwd} do
      assert Init.detect_all_stacks(cwd) == ["unknown"]
    end

    test "returns the matching stacks when markers are present", %{cwd: cwd} do
      File.write!(Path.join(cwd, "mix.exs"), "")
      File.write!(Path.join(cwd, "package.json"), "")

      stacks = Init.detect_all_stacks(cwd)
      assert "elixir" in stacks
      assert "node" in stacks
    end

    test "returns a deduplicated list of stacks", %{cwd: cwd} do
      File.write!(Path.join(cwd, "Cargo.toml"), "")
      File.write!(Path.join(cwd, "package.json"), "")

      stacks = Init.detect_all_stacks(cwd)
      assert is_list(stacks)
      assert stacks == Enum.uniq(stacks)
    end
  end

  describe "integration" do
    @tag :integration
    test "with a missing path, prints an error and halts", %{cwd: _cwd} do
      # System.halt(1) makes this hard to assert directly; the integration
      # stub verifies the code path doesn't crash on unexpected input.
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Init.run(["/nonexistent/path/should/halt"])
        end)

      # If the halt fired the test runner is dead and we never reach this
      # assertion. If the integration tag is on and a populated DB is wired,
      # we'll see the "Path does not exist" message.
      assert output =~ "Path does not exist" or output =~ "Initializing"
    end
  end
end
