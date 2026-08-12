defmodule Delfos.Benchmarks.RetrievalTest do
  use ExUnit.Case, async: true

  alias Delfos.Benchmarks.Retrieval

  describe "precision_at_k/3" do
    test "returns 1.0 when all top-k are relevant" do
      results = [
        %{name: "Auth.authenticate"},
        %{name: "Auth.middleware"},
        %{name: "Auth.token"}
      ]

      assert Retrieval.precision_at_k(results, 3, ["auth"]) == 1.0
    end

    test "returns 0.0 when no results are relevant" do
      results = [%{name: "Foo"}, %{name: "Bar"}]
      assert Retrieval.precision_at_k(results, 2, ["auth"]) == 0.0
    end

    test "fractional when only some are relevant" do
      results = [%{name: "Auth.foo"}, %{name: "Bar"}, %{name: "Baz"}]
      assert Retrieval.precision_at_k(results, 3, ["auth"]) == 1.0 / 3.0
    end

    test "matches case-insensitively" do
      results = [%{name: "AUTHENTICATE"}, %{name: "foo"}]
      assert Retrieval.precision_at_k(results, 2, ["auth"]) == 0.5
    end

    test "matches against qualified_name too" do
      results = [%{qualified_name: "MyApp.Auth.handler"}, %{name: "x"}]
      assert Retrieval.precision_at_k(results, 2, ["auth"]) == 0.5
    end
  end

  describe "mrr/2" do
    test "returns 1.0 when first result is relevant" do
      results = [%{name: "Auth.foo"}, %{name: "bar"}]
      assert Retrieval.mrr(results, ["auth"]) == 1.0
    end

    test "returns 1/n when nth result is relevant" do
      results = [%{name: "Foo"}, %{name: "Bar"}, %{name: "Auth.x"}]
      assert Retrieval.mrr(results, ["auth"]) == 1.0 / 3.0
    end

    test "returns 0.0 when no result is relevant" do
      results = [%{name: "Foo"}, %{name: "Bar"}]
      assert Retrieval.mrr(results, ["auth"]) == 0.0
    end
  end

  describe "run_eval/2" do
    test "runs all queries and aggregates" do
      mock = fn _query ->
        [%{name: "Auth.handler"}, %{name: "Other"}]
      end

      result = Retrieval.run_eval(mock, 5)

      assert result.queries_evaluated == 5
      assert result.k == 5
      assert result.avg_precision_at_k > 0.0
      assert result.avg_mrr > 0.0
      assert length(result.details) == 5
    end

    test "returns avg 0 when no queries hit" do
      miss = fn _query ->
        [%{name: "Unrelated"}]
      end

      result = Retrieval.run_eval(miss, 5)

      assert result.avg_precision_at_k == 0.0
      assert result.avg_mrr == 0.0
    end
  end
end
