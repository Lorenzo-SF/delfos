defmodule Delfos.CLI.Commands.Setup.LLM.ExternalTest do
  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Setup.LLM.External

  describe "embedding_section/3" do
    test "with openai provider returns runtime-editable keys only" do
      result = External.embedding_section(:openai, "https://api.openai.com/v1", "test-key")
      
      assert %{"embedding" => embedding_map} = result
      assert embedding_map["provider"] == "openai"
      assert embedding_map["url"] == "https://api.openai.com"
      assert embedding_map["api_key"] == "test-key"
      assert embedding_map["batch_size"] == 32
      assert embedding_map["timeout_ms"] == 30_000
      
      # Should NOT include compile-time fixed keys
      refute Map.has_key?(embedding_map, "model")
      refute Map.has_key?(embedding_map, "dim")
      refute Map.has_key?(embedding_map, "pooling")
    end

    test "with anthropic provider returns runtime-editable keys only" do
      result = External.embedding_section(:anthropic, "https://api.anthropic.com/v1", "test-key")
      
      assert %{"embedding" => embedding_map} = result
      assert embedding_map["provider"] == "openai"
      assert embedding_map["url"] == "https://api.anthropic.com"
      assert embedding_map["api_key"] == "test-key"
      assert embedding_map["batch_size"] == 32
      assert embedding_map["timeout_ms"] == 30_000
      
      # Should NOT include compile-time fixed keys
      refute Map.has_key?(embedding_map, "model")
      refute Map.has_key?(embedding_map, "dim")
      refute Map.has_key?(embedding_map, "pooling")
    end
  end

  describe "configure/4" do
    test "with target :embedding returns false and prints warning" do
      # This should abort with a warning message
      result = External.configure(:embedding, :anthropic, "https://api.anthropic.com/v1", "test-key")
      
      # Should return false to indicate aborted
      assert result == false
    end
  end

  describe "embedding_section/3 edge cases" do
    test "returned map only has runtime-editable keys (whitelist check)" do
      result = External.embedding_section(:openai, "https://api.openai.com/v1", "k")

      assert %{"embedding" => embedding_map} = result

      # Whitelist: only these keys are allowed in the runtime config.
      allowed = ~w(api_key batch_size provider timeout_ms url) |> Enum.sort()
      actual_keys = Map.keys(embedding_map) |> Enum.sort()
      assert actual_keys == allowed
    end

    test "strips trailing /v1 from URL" do
      result = External.embedding_section(:openai, "https://api.openai.com/v1/", "k")
      assert result["embedding"]["url"] == "https://api.openai.com"
    end
  end
end