defmodule Delfos.CLI.Commands.Setup.DBTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Setup.DB.

  Verifies:
    - build_options/4 (public @doc false) shapes the option list per environment
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Setup.DB, as: SetupDB

  describe "build_options/4" do
    test "returns the manual + remote + skip trio when no tools are present" do
      opts = SetupDB.build_options(false, false, false, false)
      labels = Enum.map(opts, fn {label, _atom} -> label end)

      assert Enum.any?(opts, fn {_, a} -> a == :manual end)
      assert Enum.any?(opts, fn {_, a} -> a == :remote end)
      assert Enum.any?(opts, fn {_, a} -> a == :skip end)
      # No local/detection-based options when nothing is present.
      refute Enum.any?(opts, fn {_, a} -> a == :local end)
      refute Enum.any?(opts, fn {_, a} -> a == :docker end)
      assert "Install manually (I'll do it myself)" in labels
    end

    test "includes :docker when docker is available" do
      opts = SetupDB.build_options(false, true, false, false)

      assert Enum.any?(opts, fn {label, a} ->
               a == :docker and label =~ "Docker"
             end)
    end

    test "includes :brew when homebrew is available" do
      opts = SetupDB.build_options(false, false, true, false)

      assert Enum.any?(opts, fn {label, a} ->
               a == :brew and label =~ "Homebrew"
             end)
    end

    test "includes :apt when apt-get is available" do
      opts = SetupDB.build_options(false, false, false, true)

      assert Enum.any?(opts, fn {label, a} ->
               a == :apt and label =~ "apt-get"
             end)
    end

    test "always offers :remote and :skip regardless of environment" do
      opts_empty = SetupDB.build_options(false, false, false, false)
      opts_full = SetupDB.build_options(true, true, true, true)

      for opts <- [opts_empty, opts_full] do
        assert Enum.any?(opts, fn {_, a} -> a == :remote end)
        assert Enum.any?(opts, fn {_, a} -> a == :skip end)
      end
    end
  end
end
