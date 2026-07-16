defmodule Delfos.Config.ManagerTest do
  # async: false is REQUIRED here. The setup at line 6 mutates the global
  # `Application.put_env(:delfos, :config_dir, ...)` and the "env overrides"
  # describe at line 188 mutates `System.put_env("EMBED_URL", ...)`.
  # With async: true, multiple tests in this file (or in any other file that
  # also touches these globals — see llm_discovery_candil_test, llama_cpp_test,
  # manager_legacy_test, all of which already use async: false for the same
  # reason) race against each other:
  #
  #   - Two parallel tests both call Manager.write/load; the Application env
  #     gets overwritten between them, so test A's writes end up in test B's
  #     tmp dir (data corruption).
  #
  #   - Manager.encryption_key/0 creates `<tmp>/.key` lazily. If test A's
  #     on_exit (File.rm_rf!/1) starts walking test A's tmp dir while test B
  #     (which the env-var race has routed to the SAME path) is recreating
  #     .key in that dir, the recursive walk hits "file already exists" when
  #     it tries to rmdir a directory that just got a new file in it.
  #
  # The fix would be a per-test isolation refactor of Manager.config_dir/0
  # (e.g. via :persistent_term keyed by self()), but that's out of scope for
  # this test fix. async: false keeps tests sequential, which avoids the
  # races entirely; with 22 tests running in ~100ms total it's not a
  # perf concern.
  use ExUnit.Case, async: false

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

  # Returns the compile-time LLM model filename (set via LLAMA_LLM_MODEL env
  # var or via config/config.exs default). Used by tests that compare against
  # `Manager.llm/0` output, which exposes the compile-time value as `:model`.
  # Module attribute so `Application.compile_env/3` (a compile-time macro)
  # can be invoked — it cannot be called inside functions.
  @compile_llm_model Application.compile_env(:delfos, :llm, [])[:model]

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
      assert kw[:dim] == 1536
    end

    test "llm/0 returns keyword list with defaults" do
      kw = Manager.llm()
      assert kw[:provider] == :local
      assert kw[:url] == "http://127.0.0.1:9999"
      # `model` is the *compile-time* filename (set via LLAMA_LLM_MODEL env
      # var at build time, defaulting to "gpt-oss-20b-UD-Q8_K_XL.gguf" in
      # config/config.exs). This is NOT the runtime alias — the alias lives
      # in the runtime JSON and is used only by the config UI.
      assert kw[:model] == @compile_llm_model
      assert is_binary(kw[:model])
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
