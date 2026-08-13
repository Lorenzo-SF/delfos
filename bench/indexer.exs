# Bench: Delfos.Indexer.Streaming — pipeline completo sobre fixtures
#
# Mide el tiempo total de indexar proyectos de tres tamaños.
# Este es el core de `delfos init` y `delfos scan`.

defmodule Bench.Indexer do
  def run do
    sizes = %{
      "small (10 files)" => "bench/fixtures/small",
      "medium (100 files)" => "bench/fixtures/medium",
      "large (500 files)" => "bench/fixtures/large"
    }

    # Mide: Scanner.stream_files + Enum.to_list (lo que el indexer hace)
    # Para no necesitar DB, medimos solo la fase de scanner + parser AST.
    Benchee.run(
      %{
        "scan + AST parse all files" => fn dir ->
          files =
            dir
            |> Delfos.Indexer.Scanner.stream_files([], [])
            |> Enum.to_list()

          # Por cada archivo, parsear AST (lo más caro del indexer)
          Enum.each(files, fn path ->
            try do
              path |> File.read!() |> Code.string_to_quoted!()
            rescue
              _ -> :skip
            end
          end)
        end
      },
      inputs: sizes,
      time: 5,
      memory_time: 2,
      warmup: 1,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    IO.puts("\n--- Notes ---")
    IO.puts("This excludes: DB inserts, embeddings, graph build.")
    IO.puts("Real-world delfos init adds ~50-500ms per file for embeddings.")
    IO.puts("If this is fast, the bottleneck is embedding generation, not Elixir.")
  end
end

Bench.Indexer.run()
