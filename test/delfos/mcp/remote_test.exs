defmodule Delfos.MCP.Remote.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Delfos.MCP.Remote.Router

  @opts Router.init([])

  describe "GET / (index)" do
    test "returns the help text" do
      conn = :get |> conn("/") |> Router.call(@opts)
      assert conn.status == 200
      assert conn.resp_body =~ "Delfos MCP HTTP/SSE"
    end
  end

  describe "POST /messages (JSON-RPC)" do
    test "returns method-not-found for unknown methods" do
      conn =
        :post
        |> conn("/messages", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "nope"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      [result] = body["results"]
      assert result["error"]["code"] == -32_601
    end

    test "returns invalid JSON error for malformed body" do
      conn =
        :post
        |> conn("/messages", "not json")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "Invalid JSON"
    end

    test "returns 404 for unknown paths" do
      conn = :get |> conn("/nope") |> Router.call(@opts)
      assert conn.status == 404
    end
  end
end
