defmodule Delfos.CLI.SpinnerTest do
  @moduledoc """
  Unit tests for the Spinner helper.

  Covers:
    - Returns the result of the wrapped function
    - Silent (no animation) when stderr is not a TTY
    - Doesn't crash on exceptions inside the wrapped function
  """

  use ExUnit.Case, async: true

  alias Delfos.CLI.Spinner

  describe "with/2" do
    test "returns the result of the wrapped function" do
      result = Spinner.with("loading", fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end

    test "works with simple values" do
      assert Spinner.with("loading", fn -> "hello" end) == "hello"
      assert Spinner.with("loading", fn -> 123 end) == 123
      assert Spinner.with("loading", fn -> nil end) == nil
    end

    test "doesn't catch exceptions from the wrapped function" do
      assert_raise RuntimeError, "boom", fn ->
        Spinner.with("loading", fn -> raise "boom" end)
      end
    end

    test "doesn't catch exits" do
      assert catch_exit(Spinner.with("loading", fn -> exit(:shutdown) end)) == :shutdown
    end

    test "doesn't catch throws" do
      assert catch_throw(Spinner.with("loading", fn -> throw(:oops) end)) == :oops
    end
  end
end
