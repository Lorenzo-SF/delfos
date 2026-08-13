# Bench: Delfos.Indexer.Chunker — chunk_file_path (PE-4 streaming chunker)
#
# Compara el costo de chunkear contenido pre-cargado en memoria
# vs. recargar el archivo desde disco cada vez.

defmodule Bench.Chunker do
  def run do
    sample_path =
      Path.join([
        "bench/fixtures/medium/lib",
        Enum.at(File.ls!("bench/fixtures/medium/lib"), 5)
      ])

    content = File.read!(sample_path)

    Benchee.run(
      %{
        "in-memory String.split (cached)" => fn _ ->
          content |> String.split("\n") |> length()
        end,
        "File.read! each iteration (cold I/O)" => fn _ ->
          sample_path |> File.read!() |> String.split("\n") |> length()
        end
      },
      inputs: %{"medium sample (~50 lines, ~1KB)" => sample_path},
      time: 2,
      memory_time: 1,
      warmup: 0.5,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    IO.puts("\n--- Notes ---")
    IO.puts("Cached = no I/O, just the split operation.")
    IO.puts("Cold = reloads from disk each call — what File.read! does per file.")
  end
end

Bench.Chunker.run()
