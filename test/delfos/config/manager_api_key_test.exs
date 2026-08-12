defmodule Delfos.Config.Manager.ApiKeyTest do
  use ExUnit.Case, async: false

  alias Delfos.Config.Manager

  describe "fetch_api_key!/1 (SE-4 / S15)" do
    test "returns the real api_key for :embedding" do
      assert Manager.fetch_api_key!(:embedding) == "sk-local-dev-key"
    end

    test "returns the real api_key for :llm" do
      assert Manager.fetch_api_key!(:llm) == "sk-local-dev-key"
    end

    test "returns nil for :summarize when section not present" do
      # No [summarize] section in default config; section is nil
      assert Manager.fetch_api_key!(:summarize) == nil
    end

    test "returns nil for unknown section" do
      assert Manager.fetch_api_key!(:nonexistent) == nil
      assert Manager.fetch_api_key!(nil) == nil
    end
  end

  describe "mask_api_key/1" do
    test "masks long keys: 6 chars + ... + 4 chars" do
      # sk-1234567890abcdef (length 20)
      masked = Manager.mask_api_key("sk-1234567890abcdef")
      assert masked == "sk-123...cdef"
    end

    test "fully masks short keys" do
      assert Manager.mask_api_key("short") == "*****"
      assert Manager.mask_api_key("12345678") == "********"
    end

    test "nil returns sentinel" do
      assert Manager.mask_api_key(nil) == "(no configurada)"
    end

    test "mask_api_key is safe to log (does NOT include raw value)" do
      raw = "sk-very-long-secret-key-here"
      masked = Manager.mask_api_key(raw)
      refute String.contains?(masked, raw)
      assert String.length(masked) < String.length(raw)
    end
  end
end
