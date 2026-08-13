# Bench: Delfos.Parsers.ElixirParser.real_parser — memory + time sobre múltiples archivos
#
# Mide el costo real de parsear N archivos (uno a uno, descartando AST
# entre archivos) — esto es lo que hace el indexer pipeline real.

defmodule Bench.ParserReal do
  def run do
    sizes = %{
      "small (10 files)" => "bench/fixtures/small/lib",
      "medium (100 files)" => "bench/fixtures/medium/lib",
      "large (500 files)" => "bench/fixtures/large/lib"
    }

    Benchee.run(
      %{
        "ElixirParser.parse/2 (all files in dir)" => fn dir ->
          dir
          |> File.ls!()
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.each(fn path ->
            content = File.read!(path)
            # El parser hace TODO el trabajo; descartamos el resultado
            _result = Delfos.Parsers.ElixirParser.parse(path, content)
            :ok
          end)
        end
      },
      inputs: sizes,
      time: 3,
      memory_time: 2,
      warmup: 1,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    IO.puts("\n--- Notes ---")
    IO.puts("El resultado se descarta a propósito — medimos solo el coste del parse.")
    IO.puts("El AST no se mantiene entre archivos (cada iteración libera su memoria).")
  end
end

Bench.ParserReal.run()
