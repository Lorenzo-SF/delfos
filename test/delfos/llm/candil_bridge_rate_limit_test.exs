defmodule Delfos.LLM.CandilBridgeRateLimitTest do
  use ExUnit.Case, async: true

  alias Delfos.LLM.CandilBridge

  describe "rate_limit_enabled?/0 (iter-051)" do
    test "returns boolean (true or false depending on env)" do
      result = CandilBridge.rate_limit_enabled?()
      assert is_boolean(result)
    end
  end

  describe "check_rate_limit/0 (iter-051)" do
    test "returns :ok when rate limiting disabled (Apero unavailable)" do
      if CandilBridge.rate_limit_enabled?() do
        result = CandilBridge.check_rate_limit()
        assert result == :ok or result == {:error, :rate_limited}
      else
        assert CandilBridge.check_rate_limit() == :ok
      end
    end
  end
end
