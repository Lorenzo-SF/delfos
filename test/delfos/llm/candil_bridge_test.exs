defmodule Delfos.LLM.CandilBridgeTest do
  use ExUnit.Case, async: true

  alias Delfos.LLM.CandilBridge

  describe "normalize/1 (C8)" do
    test "normalizes a unit-norm vector to itself" do
      v = [0.6, 0.8]
      n = CandilBridge.normalize(v)
      # ||v|| = sqrt(0.36 + 0.64) = 1.0, so stays the same
      assert_vectors_equal(n, [0.6, 0.8])
    end

    test "normalizes an arbitrary vector to unit norm" do
      v = [3.0, 4.0]
      n = CandilBridge.normalize(v)
      assert_vectors_equal(n, [0.6, 0.8])
      # verify unit norm
      norm = :math.sqrt(Enum.sum(Enum.map(n, &(&1 * &1))))
      assert_in_delta norm, 1.0, 1.0e-9
    end

    test "returns nil for zero vector" do
      assert CandilBridge.normalize([0.0, 0.0, 0.0]) == nil
    end

    test "returns nil for non-list input" do
      assert CandilBridge.normalize(nil) == nil
      assert CandilBridge.normalize("not a vec") == nil
      assert CandilBridge.normalize([]) == nil
    end

    test "normalization is idempotent" do
      v = [5.0, 12.0]
      once = CandilBridge.normalize(v)
      twice = CandilBridge.normalize(once)
      assert once == twice
    end
  end

  defp assert_vectors_equal(actual, expected, tolerance \\ 1.0e-9) do
    assert length(actual) == length(expected),
           "vector length mismatch: #{inspect(actual)} vs #{inspect(expected)}"

    Enum.zip(actual, expected)
    |> Enum.with_index()
    |> Enum.each(fn {pair, i} ->
      assert_in_delta elem(pair, 0), elem(pair, 1), tolerance,
                     "element #{i}: #{inspect(actual)} vs #{inspect(expected)}"
    end)
  end
end
