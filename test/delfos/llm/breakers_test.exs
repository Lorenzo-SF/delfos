defmodule Delfos.LLM.BreakersTest do
  use ExUnit.Case, async: false

  alias Delfos.LLM.Breakers

  describe "name_for/1" do
    test "generates correct breaker name for valid URL" do
      url = "https://api.anthropic.com/v1/messages"
      expected = :delfos_llm_breaker_api_anthropic_com
      assert Breakers.name_for(url) == expected
    end

    test "returns default breaker for invalid URL" do
      assert Breakers.name_for("not a url") == :delfos_llm_default_breaker
      assert Breakers.name_for(nil) == :delfos_llm_default_breaker
    end
  end

  describe "child_spec/1" do
    test "returns valid supervisor child spec" do
      spec = Breakers.child_spec(:test_breaker)
      assert is_tuple(spec.id)
      # The start field is a tuple with function name and arguments
      assert is_tuple(spec.start)
      assert spec.type == :worker
      assert spec.restart == :permanent
    end
  end

  describe "ensure_running/1" do
    test "starts the breaker if not registered" do
      # Use a unique name per test run to avoid collisions with other tests
      # or with the application supervision tree.
      name = :"delfos_test_breaker_#{System.unique_integer([:positive])}"

      # Initially not registered.
      assert Registry.lookup(Arrea.CircuitBreaker.Registry, name) == []

      # After ensure_running, it should be registered and reachable.
      assert Breakers.ensure_running(name) == :ok

      assert [{_pid, _}] = Registry.lookup(Arrea.CircuitBreaker.Registry, name)

      # Calling again is a no-op (idempotent).
      assert Breakers.ensure_running(name) == :ok
    end

    test "is a no-op when the breaker is already running" do
      name = :"delfos_test_breaker_already_#{System.unique_integer([:positive])}"
      assert Breakers.ensure_running(name) == :ok
      # Second call: still :ok (returns {:error, {:already_started, _}} which
      # the helper normalises to :ok).
      assert Breakers.ensure_running(name) == :ok
    end
  end
end
