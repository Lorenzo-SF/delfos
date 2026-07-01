defmodule Delfos.MCP.ServerTest do
  @moduledoc """
  Unit tests for Delfos.MCP.Server.

  Verifies the pure helpers extracted for testability:
    - build_tool_response/2 wraps {:ok, _} and {:error, _} into proper
      JSON-RPC 2.0 response maps
    - dispatch_tool/3 routes known tool names and returns errors for unknown ones
    - The tool timeout constant is exposed for assertion
  """

  use ExUnit.Case, async: false

  alias Delfos.MCP.Server

  describe "build_tool_response/2" do
    test "wraps {:ok, content} in a result envelope with a text content block" do
      response = Server.build_tool_response("req-1", {:ok, "hello world"})

      assert response.jsonrpc == "2.0"
      assert response.id == "req-1"

      assert is_map(response.result)
      assert is_list(response.result.content)
      assert length(response.result.content) == 1

      [block] = response.result.content
      assert block.type == "text"
      assert block.text == "hello world"

      refute Map.has_key?(response.result, :isError)
    end

    test "wraps {:error, reason} in a result envelope flagged as isError" do
      response = Server.build_tool_response("req-2", {:error, "boom"})

      assert response.jsonrpc == "2.0"
      assert response.id == "req-2"

      assert response.result.isError == true

      [block] = response.result.content
      assert block.type == "text"
      assert block.text =~ "Error"
      assert block.text =~ "boom"
    end

    test "accepts integer ids (JSON-RPC spec)" do
      response = Server.build_tool_response(42, {:ok, "x"})
      assert response.id == 42
    end

    test "accepts nil ids (for parse errors where the id is unknown)" do
      response = Server.build_tool_response(nil, {:error, "parse"})
      assert response.id == nil
    end

    test "supports multi-line text content" do
      text = "line 1\nline 2\nline 3"
      response = Server.build_tool_response("req-3", {:ok, text})

      [block] = response.result.content
      assert block.text =~ "line 1"
      assert block.text =~ "line 3"
    end
  end

  describe "dispatch_tool/3" do
    test "returns {:error, _} for unknown tool names" do
      # Tools.* functions would hit the DB and fail without integration,
      # so we only assert the dispatch fallback for unknown names.
      assert {:error, msg} = Server.dispatch_tool("delfos_not_a_real_tool", nil, %{})
      assert msg =~ "delfos_not_a_real_tool"
      assert msg =~ "desconocida"
    end
  end

  describe "__tool_timeout_ms__/0" do
    test "is positive and within a sane range for LLM-backed tools" do
      ms = Server.__tool_timeout_ms__()
      assert is_integer(ms)
      assert ms > 1_000
      # Cap at 5 minutes — anything longer should be a separate concern.
      assert ms <= 300_000
    end
  end

  describe "JSON-RPC envelope shape" do
    test "every response includes the jsonrpc version field" do
      for result <- [{:ok, "x"}, {:error, "y"}] do
        response = Server.build_tool_response(1, result)
        assert response.jsonrpc == "2.0"
      end
    end
  end
end
