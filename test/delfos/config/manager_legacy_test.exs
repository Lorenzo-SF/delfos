defmodule Delfos.Config.ManagerLegacyJsonTest do
  @moduledoc """
  Regression test: old config.json files (pre-2.3.0 schema with
  `provider`, `url`, `model`, `gguf_path`, ...) should load transparently:
  manager normalizes url → ip/port and provider → type, and no longer
  exposes server-management fields (`gguf_path`, `llama_server_path`,
  `download_precompiled`, `launcher`, `extra_args`, `slot_dir`).
  """

  use ExUnit.Case, async: false

  alias Delfos.Config.Manager

  setup do
    tmp =
      Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_legacy_test")

    File.mkdir_p!(tmp)
    Application.put_env(:delfos, :config_dir, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:delfos, :config_dir)
    end)

    :ok
  end

  test "embedding/0 normalizes legacy url to ip/port and provider to openai" do
    File.write!(
      Manager.config_file(),
      Jason.encode!(%{
        "embedding" => %{
          "provider" => "local",
          "url" => "http://127.0.0.1:9998",
          "model" => "bge-m3",
          "api_key" => "sk-test"
        },
        "llm" => %{
          "provider" => "local",
          "url" => "http://127.0.0.1:8080",
          "model" => "Qwen2.5-Coder-3B-Instruct",
          "api_key" => "sk-test"
        }
      })
    )

    embedding = Manager.embedding()

    assert embedding[:ip] == "127.0.0.1"
    assert embedding[:port] == 9998
    assert embedding[:url] == "http://127.0.0.1:9998"
    assert embedding[:provider] == :openai
    assert embedding[:type] == "openai"

    # Server-management fields are gone
    refute Keyword.has_key?(embedding, :gguf_path)
    refute Keyword.has_key?(embedding, :llama_server_path)
    refute Keyword.has_key?(embedding, :download_precompiled)
    refute Keyword.has_key?(embedding, :launcher)
    refute Keyword.has_key?(embedding, :extra_args)
  end

  test "llm/0 normalizes legacy url to ip/port and provider to type" do
    File.write!(
      Manager.config_file(),
      Jason.encode!(%{
        "embedding" => %{"url" => "http://127.0.0.1:9998"},
        "llm" => %{
          "provider" => "anthropic",
          "url" => "https://api.anthropic.com",
          "model" => "claude-sonnet-4-20250514",
          "api_key" => "sk-test"
        }
      })
    )

    llm = Manager.llm()

    assert llm[:ip] == "api.anthropic.com"
    assert llm[:port] == 443
    assert llm[:type] == "anthropic"
    assert llm[:provider] == :anthropic
    assert llm[:url] == "https://api.anthropic.com:443"
    assert llm[:model] == "claude-sonnet-4-20250514"

    refute Keyword.has_key?(llm, :thinker_url)
    refute Keyword.has_key?(llm, :thinker_model)
    refute Keyword.has_key?(llm, :gguf_path)
  end

  test "load/0 returns the full default map when no file exists" do
    cfg = Manager.load()
    assert cfg["embedding"]["ip"] == "127.0.0.1"
    assert cfg["llm"]["ip"] == "127.0.0.1"
    assert cfg["llm"]["type"] == "openai"
    refute Map.has_key?(cfg["embedding"], "gguf_path")
    refute Map.has_key?(cfg["llm"], "launcher")
  end
end