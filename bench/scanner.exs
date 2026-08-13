# Bench: Delfos.Indexer.Scanner — find_files vs stream_files
#
# Mide cuánto tarda el scanner en recorrer proyectos de tres tamaños.
# Esto es la primera operación de `delfos init` y `delfos scan`.

Code.require_file("fixtures.exs", "bench/")

defmodule Bench.Scanner do
  def run do
    sizes = [:small, :medium, :large]

    Benchee.run(
      %{
        "find_files/2" => fn input -> Delfos.Indexer.Scanner.find_files(input, []) |> Enum.to_list() end,
        "stream_files/3" => fn input -> Delfos.Indexer.Scanner.stream_files(input, [], []) |> Enum.to_list() end
      },
      inputs: %{
        "small (10 files)" => "bench/fixtures/small",
        "medium (100 files)" => "bench/fixtures/medium",
        "large (500 files)" => "bench/fixtures/large"
      },
      time: 2,
      memory_time: 1,
      warmup: 0.5,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    IO.puts("\n--- Notes ---")
    IO.puts("PE-1: stream_files was supposed to replace find_files for memory reasons.")
    IO.puts("If find_files is faster, the materialization isn't a hot path concern here.")
    IO.puts("If stream_files is dramatically slower, the Stream.resource overhead matters.")
  end
end

# Need to have fixtures in place — if missing, build them
unless File.exists?("bench/fixtures/largest/lib") do
  Bench.Fixtures.build_all()
end

Bench.Scanner.run()
