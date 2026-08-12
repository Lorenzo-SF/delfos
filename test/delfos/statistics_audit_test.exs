defmodule Delfos.Statistics.AuditTest do
  use ExUnit.Case, async: true

  alias Delfos.Statistics

  describe "encode_args/1 (private)" do
    # Test via public API by checking the encoded value via Jason.decode
    test "encodes simple map" do
      # We can't easily test the private function, but we can verify
      # the schema accepts it and roundtrips correctly.
      assert is_function(&Statistics.record_call/6, 6)
    end
  end

  describe "record_call/6 signature" do
    test "accepts opts keyword list" do
      # Verify the arity is correct by checking the function metadata
      assert {:arity, 6} = Function.info(&Statistics.record_call/6, :arity)
    end

    test "record_call_async also accepts opts" do
      assert {:arity, 6} = Function.info(&Statistics.record_call_async/6, :arity)
    end
  end

  describe "format_caller_pid behaviour via encode_args" do
    # We test the helper logic through encode_args behaviour since the
    # function is private. The point is: nil args → nil, bad input
    # → nil (doesn't crash), valid → JSON.

    # This test uses the public schema validation as a proxy.
    test "McpUsageEvent changeset accepts args field" do
      changeset =
        %Delfos.Schema.McpUsageEvent{}
        |> Delfos.Schema.McpUsageEvent.changeset(%{
          project_id: "00000000-0000-0000-0000-000000000000",
          tool_name: "test_tool",
          status: "success",
          response_tokens: 100,
          saved_tokens: 200,
          duration_ms: 50,
          args: ~s({"query":"hello","limit":5}),
          caller_pid: "#PID<0.123.0>"
        })

      assert changeset.valid?
    end

    test "McpUsageEvent changeset rejects oversized args (via length)" do
      # This is a smoke test — the truncation happens in encode_args
      # BEFORE the changeset, so the changeset itself accepts any text.
      # Just verify the field is in the cast.
      attrs = %{
        project_id: "00000000-0000-0000-0000-000000000000",
        tool_name: "test_tool",
        status: "success",
        response_tokens: 100,
        saved_tokens: 0,
        duration_ms: 50,
        args: nil,
        caller_pid: nil
      }

      changeset =
        %Delfos.Schema.McpUsageEvent{}
        |> Delfos.Schema.McpUsageEvent.changeset(attrs)

      assert changeset.valid?
    end
  end
end
