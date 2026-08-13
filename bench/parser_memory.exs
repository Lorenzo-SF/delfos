# Bench: ElixirParser AST memory — naive vs streaming
#
# Compara dos estrategias de parsing:
#   1. Naive: Code.string_to_quoted! + Macro.prewalk con lista acumulada
#   2. Streaming: Code.string_to_quoted/2 + Macro.prewalk + procesar y descartar
#
# Objetivo: probar que procesar sin acumular reduce la memoria peak sin
# penalizar tiempo.

defmodule Bench.ParserMemory do
  def run do
    sample_path =
      Path.join([
        "bench/fixtures/medium/lib",
        Enum.at(File.ls!("bench/fixtures/medium/lib"), 5)
      ])

    content = File.read!(sample_path)
    lines = String.split(content, "\n")

    # Reproducir el flujo del ElixirParser actual pero midiendo memoria peak.
    # Estrategia 1 (naive): reproduce el código de lib/delfos/parsers/elixir_parser.ex
    naive = fn _ ->
      {:ok, ast} = Code.string_to_quoted(content, columns: true, line: 1)

      {_, acc} =
        Macro.prewalk(ast, [], fn node, acc -> {node, [node | acc]} end)

      # Aquí simulamos el "extract_top_level" que consume el acc
      length(acc)
    end

    # Estrategia 2 (streaming): procesar nodo por nodo sin acumular
    streaming = fn _ ->
      {:ok, ast} = Code.string_to_quoted(content, columns: true, line: 1)

      counter =
        Macro.prewalk(ast, 0, fn
          {:defmodule, _, _}, acc -> {nil, acc + 1}
          {:def, _, _}, acc -> {nil, acc + 1}
          {:defp, _, _}, acc -> {nil, acc + 1}
          _, acc -> {nil, acc}
        end)

      counter
    end

    # Estrategia 3 (Code.Parser sólo — sin parsear)
    parse_only = fn _ ->
      Code.string_to_quoted!(content)
      :ok
    end

    Benchee.run(
      %{
        "naive (prewalk + acc list)" => naive,
        "streaming (prewalk + counter)" => streaming,
        "string_to_quoted! only" => parse_only
      },
      inputs: %{"medium module (~50 lines)" => :noop},
      time: 3,
      memory_time: 2,
      warmup: 1,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    IO.puts("\n--- Notes ---")
    IO.puts("naive = current implementation (allocates all visited nodes)")
    IO.puts("streaming = count-only, no list allocation")
    IO.puts("string_to_quoted! only = AST construction cost")
    IO.puts("Memory delta = cost of the acc list per parse")
  end
end

Bench.ParserMemory.run()
