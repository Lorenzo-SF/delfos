defmodule Delfos.Config.ManagerLegacyJsonTest do
  @moduledoc """
  Regression test: old config.json files (pre-2.2.1 schema with only
  `provider`, `url`, `model`, etc.) should load transparently with
  sensible defaults for the new fields (`extra_args`, `gguf_path`,
  `llama_server_path`, `download_precompiled`, `launcher`).
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

  test "embedding/0 returns defaults for fields absent in old configs" do
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

    assert embedding[:extra_args] == []
    assert embedding[:gguf_path] == nil
    assert embedding[:llama_server_path] == nil
    assert embedding[:download_precompiled] == true
    assert embedding[:launcher] == nil
  end

  test "llm/0 returns defaults for fields absent in old configs" do
    File.write!(
      Manager.config_file(),
      Jason.encode!(%{
        "embedding" => %{"url" => "http://127.0.0.1:9998"},
        "llm" => %{
          "provider" => "local",
          "url" => "http://127.0.0.1:8080",
          "model" => "Qwen2.5-Coder-3B-Instruct",
          "api_key" => "sk-test"
        }
      })
    )

    llm = Manager.llm()

    assert llm[:extra_args] == []
    assert llm[:gguf_path] == nil
    assert llm[:llama_server_path] == nil
    assert llm[:download_precompiled] == true
    assert llm[:launcher] == nil
  end

  test "load/0 returns the full default map when no file exists" do
    cfg = Manager.load()
    assert cfg["embedding"]["gguf_path"] == nil
    assert cfg["embedding"]["llama_server_path"] == nil
    assert cfg["embedding"]["download_precompiled"] == true
    assert cfg["embedding"]["launcher"] == nil
    assert cfg["llm"]["gguf_path"] == nil
    assert cfg["llm"]["llama_server_path"] == nil
    assert cfg["llm"]["download_precompiled"] == true
    assert cfg["llm"]["launcher"] == nil
  end
end
