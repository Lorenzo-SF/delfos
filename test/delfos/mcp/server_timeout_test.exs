defmodule Delfos.MCP.ServerTimeoutTest do
  use ExUnit.Case, async: true

  alias Delfos.MCP.Server

  describe "tool_timeout_ms_from_env/0 (iter-051 env override)" do
    setup do
      original = System.get_env("DELFOS_TOOL_TIMEOUT_MS")
      on_exit(fn ->
        if original do
          System.put_env("DELFOS_TOOL_TIMEOUT_MS", original)
        else
          System.delete_env("DELFOS_TOOL_TIMEOUT_MS")
        end
      end)
      :ok
    end

    test "returns default when env var not set" do
      System.delete_env("DELFOS_TOOL_TIMEOUT_MS")
      assert Server.tool_timeout_ms_from_env() == Server.tool_timeout_ms()
    end

    test "returns default when env var is empty" do
      System.put_env("DELFOS_TOOL_TIMEOUT_MS", "")
      assert Server.tool_timeout_ms_from_env() == Server.tool_timeout_ms()
    end

    test "returns parsed value when env var is a positive integer" do
      System.put_env("DELFOS_TOOL_TIMEOUT_MS", "12000")
      assert Server.tool_timeout_ms_from_env() == 12_000
    end

    test "returns default when env var is invalid" do
      System.put_env("DELFOS_TOOL_TIMEOUT_MS", "not-a-number")
      assert Server.tool_timeout_ms_from_env() == Server.tool_timeout_ms()
    end

    test "returns default when env var is zero" do
      System.put_env("DELFOS_TOOL_TIMEOUT_MS", "0")
      assert Server.tool_timeout_ms_from_env() == Server.tool_timeout_ms()
    end

    test "returns default when env var is negative" do
      System.put_env("DELFOS_TOOL_TIMEOUT_MS", "-1")
      assert Server.tool_timeout_ms_from_env() == Server.tool_timeout_ms()
    end
  end
end
