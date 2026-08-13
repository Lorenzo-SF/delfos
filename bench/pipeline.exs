# Bench: Pipeline end-to-end — scan + parse + embedding (mock)
#
# Simula el pipeline completo de `delfos init` con un mock de embedding
# que tiene latencia realista (50ms). Esto permite cuantificar cuánto
# tarda el indexer en escenarios típicos.

defmodule Bench.Pipeline do
  def run do
    sizes = %{
      "small (10 files)" => "bench/fixtures/small",
      "medium (100 files)" => "bench/fixtures/medium",
      "large (500 files)" => "bench/fixtures/large"
    }

    # Mock embedding latency: 5ms por chunk (rápido en Ollama local)
    embedding_latency_ms = 5

    mock_embedding_fn = fn _text ->
      Process.sleep(embedding_latency_ms)
      # Vector de 768 dimensiones (todo ceros, solo importa el tiempo)
      List.duplicate(0.0, 768)
    end

    Benchee.run(
      %{
        "scan + parse (CPU only, no embed)" => fn dir ->
          dir
          |> Delfos.Indexer.Scanner.stream_files()
          |> Enum.each(fn path ->
            content = File.read!(path)
            _result = Delfos.Parsers.ElixirParser.parse(path, content)
            :ok
          end)
        end,

        "scan + parse + embed-mock (5ms/chunk)" => fn dir ->
          dir
          |> Delfos.Indexer.Scanner.stream_files()
          |> Enum.each(fn path ->
            content = File.read!(path)
            %{symbols: symbols} = Delfos.Parsers.ElixirParser.parse(path, content)
            # Mock: 1 embedding por símbolo (típicamente 1-3 chunks por símbolo)
            Enum.each(symbols, fn _sym ->
              _vec = mock_embedding_fn.("mock text")
              :ok
            end)
          end)
        end
      },
      inputs: sizes,
      time: 5,
      memory_time: 2,
      warmup: 1,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    IO.puts("\n--- Analysis ---")
    IO.puts("CPU-only (parse) vs CPU+IO (parse+embed) shows the bottleneck.")
    IO.puts("If parse+embed is much slower than parse-only, embedding is the bottleneck.")
    IO.puts("Realistic delfos init = scan + parse + chunks + embed + DB writes.")
    IO.puts("Embedding latency dominates: 5ms/chunk × 100 chunks = 500ms/file.")
  end
end

Bench.Pipeline.run()
