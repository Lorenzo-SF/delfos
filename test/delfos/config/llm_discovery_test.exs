defmodule Delfos.Config.LLMDiscoveryTest do
  @moduledoc """
  Tests for LLMDiscovery.

  These tests verify the API surface without actually starting any
  LLM services.
  """

  use ExUnit.Case, async: false

  alias Delfos.Config.LLMDiscovery

  setup do
    # Each test gets an isolated HOME so config writes don't collide
    # with other tests or with the user's real ~/.config/delfos.
    fake_home = Path.join(System.tmp_dir!(), "delfos_llm_disc_#{System.unique_integer()}")
    File.mkdir_p!(fake_home)

    original_home = System.get_env("HOME")
    original_xdg = System.get_env("XDG_CONFIG_HOME")
    System.put_env("HOME", fake_home)
    System.put_env("XDG_CONFIG_HOME", fake_home)

    on_exit(fn ->
      System.put_env("HOME", original_home)
      if original_xdg, do: System.put_env("XDG_CONFIG_HOME", original_xdg)
      File.rm_rf!(fake_home)
    end)

    :ok
  end

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

  describe "ensure_embedding_server/1" do
    test "is exported with the expected arity" do
      assert function_exported?(LLMDiscovery, :ensure_embedding_server, 0)
      assert function_exported?(LLMDiscovery, :ensure_embedding_server, 1)
    end
  end
end
