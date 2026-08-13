# Bench: Delfos.Config.Manager — load + decrypt on cold vs warm cache
#
# El Manager descifra el config.json con AES-256-GCM al primer load.
# Después, lecturas repetidas deberían ser O(1) (cache en memoria).
#
# Mide:
#   1. Carga cold (primer load — descifra AES-256-GCM)
#   2. Carga warm (siguientes loads — debería ser cache O(1))
#   3. Getter específico (indexing/0, embedding/0)

defmodule Bench.Manager do
  def run do
    tmp = Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_bench")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    Application.put_env(:delfos, :config_dir, tmp)

    config = %{
      "embedding" => %{
        "provider" => "ollama",
        "url" => "http://localhost:11434",
        "model" => "nomic-embed-text",
        "dim" => 768
      },
      "llm" => %{
        "provider" => "ollama",
        "url" => "http://localhost:11434",
        "model" => "qwen2.5-coder:7b"
      },
      "indexing" => %{
        "max_depth" => 50,
        "max_files" => 500_000,
        "ignore_dirs" => ["deps", "_build", "node_modules"]
      }
    }

    Delfos.Config.Manager.write(config)
    # Pre-load to cache
    Delfos.Config.Manager.load()

    Benchee.run(
      %{
        "load/0 (warm)" => fn _ -> Delfos.Config.Manager.load() end,
        "indexing/0" => fn _ -> Delfos.Config.Manager.indexing() end,
        "embedding/0" => fn _ -> Delfos.Config.Manager.embedding() end,
        "llm/0" => fn _ -> Delfos.Config.Manager.llm() end
      },
      inputs: %{"cached config" => :noop},
      time: 2,
      memory_time: 1,
      warmup: 0.5,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    File.rm_rf!(tmp)
    Application.delete_env(:delfos, :config_dir)
  end
end

Bench.Manager.run()
