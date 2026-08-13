# Bench: Delfos.Config.Manager — cold load + decrypt vs warm
#
# Cold: load() que tiene que leer disco + descifrar AES-256-GCM.
# Warm: load() subsiguiente con cache poblado.
#
# El descifrado AES es la operación CPU-bound real. Para configs grandes
# con muchas claves cifradas, este es el hot path en arranque.

defmodule Bench.ManagerCold do
  def run do
    # Setup: crear config grande (50 secciones cifradas)
    tmp = Path.expand(System.unique_integer([:positive]) |> to_string(), "/tmp/delfos_bench_cold")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    Application.put_env(:delfos, :config_dir, tmp)

    big_config = %{
      "embedding" => %{"provider" => "ollama", "url" => "http://localhost:11434"},
      "llm" => %{"provider" => "ollama", "url" => "http://localhost:11434"},
      "indexing" => %{"max_depth" => 50}
    }
    # Añadir 50 secciones extra para inflar el JSON
    big_config =
      Enum.reduce(1..50, big_config, fn i, acc ->
        Map.put(acc, "section_#{i}", %{"key" => "value#{i}", "secret" => "secret_value_#{i}"})
      end)

    Delfos.Config.Manager.write(big_config)

    # Función que limpia el cache antes de cada call (forzar cold path)
    clear_cache = fn ->
      # Manager es Agent-backed; no hay API pública para invalidar.
      # Workaround: matar el Agent forzando restart vía Application.
      Application.stop(:delfos)
      Application.start(:delfos)
    end

    # Pre-cargar (warm)
    Delfos.Config.Manager.load()

    # Medir warm (subsiguiente load — debería ser O(1))
    Benchee.run(
      %{
        "load/0 (warm — cached)" => fn _ -> Delfos.Config.Manager.load() end,
        "indexing/0 (warm)" => fn _ -> Delfos.Config.Manager.indexing() end
      },
      inputs: %{"50-section config" => :noop},
      time: 2,
      memory_time: 1,
      warmup: 0.5,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    # Cold: medir restart + load
    IO.puts("\n--- Cold path: Application restart + first load ---")
    {cold_time_us, _} =
      :timer.tc(fn ->
        Application.stop(:delfos)
        Application.start(:delfos)
        Delfos.Config.Manager.load()
      end)

    IO.puts("Cold restart+load+decrypt: #{cold_time_us / 1000} ms")

    File.rm_rf!(tmp)
    Application.delete_env(:delfos, :config_dir)
  end
end

Bench.ManagerCold.run()
