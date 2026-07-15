defmodule Delfos.Config.ManagerTest do
  use ExUnit.Case, async: true

  alias Delfos.Config.Manager

  setup do
    # Sandbox: each test gets its own temp dir so no test touches
    # the real ~/.config/delfos.
    tmp = Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_test")
    File.mkdir_p!(tmp)
    Application.put_env(:delfos, :config_dir, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:delfos, :config_dir)
    end)

    %{tmp: tmp}
  end

  # ── Path helpers ──────────────────────────────────────────────────────────

  describe "paths" do
    test "config_file/0 returns the full path" do
      assert String.ends_with?(Manager.config_file(), "config.json")
    end

    test "legacy_config_file/0 returns the full path" do
      assert String.ends_with?(Manager.legacy_config_file(), "delfos.conf")
    end
  end

  # ── Defaults ──────────────────────────────────────────────────────────────

  describe "defaults" do
    test "default_config_content/0 returns valid JSON" do
      json = Manager.default_config_content()
      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
      assert decoded["embedding"]["provider"] == "local"
    end

    test "load/0 returns full default map when no file exists" do
      cfg = Manager.load()
      assert cfg["embedding"]["provider"] == "local"
      assert cfg["llm"]["provider"] == "local"
      assert cfg["retrieval"]["vector_weight"] == 0.55
      assert cfg["indexing"]["max_chunk_tokens"] == 512
    end

    test "load/0 creates config file on first access" do
      Manager.load()
      assert File.exists?(Manager.config_file())
    end
  end

  # ── Write / Read round-trip ───────────────────────────────────────────────

  describe "write + load round-trip" do
    test "write/1 persists and load/1 retrieves" do
      data = %{
        "embedding" => %{"provider" => "ollama", "url" => "http://localhost:11434"},
        "llm" => %{"provider" => "ollama", "model" => "llama3"}
      }

      Manager.write(data)
      cfg = Manager.load()

      assert cfg["embedding"]["provider"] == "ollama"
      assert cfg["llm"]["model"] == "llama3"
    end

    test "write/1 encrypts api_key fields" do
      Manager.write(%{
        "embedding" => %{"api_key" => "sk-my-secret"},
        "llm" => %{}
      })

      raw = File.read!(Manager.config_file())
      assert raw =~ "enc:"
      refute raw =~ "sk-my-secret"
    end

    test "load/1 decrypts api_key fields" do
      Manager.write(%{
        "embedding" => %{"api_key" => "sk-my-secret"},
        "llm" => %{}
      })

      cfg = Manager.load()
      assert cfg["embedding"]["api_key"] == "sk-my-secret"
    end

    test "re-encrypting an already encrypted value is idempotent" do
      Manager.write(%{
        "embedding" => %{"api_key" => "sk-original"},
        "llm" => %{}
      })

      Manager.write(%{
        "embedding" => %{"api_key" => "sk-original"},
        "llm" => %{}
      })

      cfg = Manager.load()
      assert cfg["embedding"]["api_key"] == "sk-original"
    end
  end

  # ── Section accessors ────────────────────────────────────────────────────

  describe "section accessors" do
    test "embedding/0 returns keyword list with defaults" do
      kw = Manager.embedding()
      assert Keyword.keyword?(kw)
      assert kw[:provider] == :local
      assert kw[:dim] == 4096
    end

    test "llm/0 returns keyword list with defaults" do
      kw = Manager.llm()
      assert kw[:provider] == :local
      assert kw[:url] == "http://127.0.0.1:9999"
      assert kw[:model] == "gpt-oss"
      assert kw[:thinker_model] == nil
      assert kw[:thinker_url] == nil
    end

    test "retrieval/0 returns keyword list" do
      kw = Manager.retrieval()
      assert kw[:vector_weight] == 0.55
      assert kw[:final_k] == 7
    end

    test "analysis/0 returns keyword list" do
      kw = Manager.analysis()
      assert kw[:churn_max_commits] == 1000
    end

    test "indexing/0 returns keyword list" do
      kw = Manager.indexing()
      assert kw[:max_chunk_tokens] == 512
      assert length(kw[:ignore_dirs]) > 5
    end
  end

  # ── set/3 ─────────────────────────────────────────────────────────────────

  describe "set/3" do
    test "sets a nested key and persists" do
      assert :ok = Manager.set("embedding", "provider", "ollama")
      cfg = Manager.load()
      assert cfg["embedding"]["provider"] == "ollama"
    end

    test "creates intermediate sections when needed" do
      assert :ok = Manager.set("custom", "flag", "true")
      cfg = Manager.load()
      assert cfg["custom"]["flag"] == "true"
    end
  end

  # ── show/0 ────────────────────────────────────────────────────────────────

  describe "show/0" do
    test "returns formatted string" do
      output = Manager.show()
      assert output =~ "Fichero:"
      assert output =~ "provider"
      assert output =~ "api_key"
    end

    test "masks api keys in output" do
      Manager.write(%{
        "embedding" => %{"api_key" => "sk-abcdefghijklmnop"},
        "llm" => %{"api_key" => "sk-1234"}
      })

      output = Manager.show()
      refute output =~ "sk-abcdefghijklmnop"
      assert output =~ "***"
    end
  end

  # ── Env overrides ─────────────────────────────────────────────────────────

  describe "env overrides" do
    setup do
      System.put_env("EMBED_URL", "http://env-override:9999")
      System.put_env("LLM_MODEL", "env-model")

      on_exit(fn ->
        System.delete_env("EMBED_URL")
        System.delete_env("LLM_MODEL")
      end)

      :ok
    end

    test "load/0 applies env overrides on top of file config" do
      Manager.write(%{
        "embedding" => %{"url" => "http://file:9999"},
        "llm" => %{"model" => "file-model"}
      })

      cfg = Manager.load()
      assert cfg["embedding"]["url"] == "http://env-override:9999"
      assert cfg["llm"]["model"] == "env-model"
    end
  end

  # ── Edge cases ────────────────────────────────────────────────────────────

  describe "edge cases" do
    test "load/0 handles corrupt JSON gracefully" do
      File.mkdir_p!(Path.dirname(Manager.config_file()))
      File.write!(Manager.config_file(), "this is not json")
      cfg = Manager.load()
      assert cfg["embedding"]["provider"] == "local"
    end

    test "load/0 handles empty file gracefully" do
      File.mkdir_p!(Path.dirname(Manager.config_file()))
      File.write!(Manager.config_file(), "")
      cfg = Manager.load()
      assert cfg["embedding"]["provider"] == "local"
    end

    test "missing config directory is autocreated" do
      File.rm_rf!(Path.dirname(Manager.config_file()))
      refute File.exists?(Path.dirname(Manager.config_file()))
      Manager.load()
      assert File.exists?(Manager.config_file())
    end
  end
end
