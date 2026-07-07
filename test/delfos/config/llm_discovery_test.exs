defmodule Delfos.Config.LLMDiscoveryTest do
  @moduledoc """
  Tests for LLMDiscovery.

  These tests verify the API surface without actually starting any
  LLM services.
  """

  use ExUnit.Case, async: true

  alias Delfos.Config.LLMDiscovery

  test "status/0 returns a list of two endpoint statuses" do
    statuses = LLMDiscovery.status()
    assert length(statuses) == 2

    roles = Enum.map(statuses, & &1.role) |> Enum.sort()
    assert roles == [:embed, :llm]
  end

  test "each endpoint status has required keys" do
    statuses = LLMDiscovery.status()

    Enum.each(statuses, fn ep ->
      assert Map.has_key?(ep, :role)
      assert Map.has_key?(ep, :url)
      assert Map.has_key?(ep, :reachable)
      assert is_boolean(ep.reachable)
    end)
  end

  test "ensure_running/0 is callable" do
    # Note: don't actually run yes-mode in tests since it would try to
    # start ollama. Just verify the function is callable.
    assert function_exported?(LLMDiscovery, :ensure_running, 0)
    assert function_exported?(LLMDiscovery, :ensure_running, 1)
  end
end
