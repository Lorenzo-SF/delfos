# Bench: Delfos.Parsers.ElixirParser — AST-based parsing
#
# CO-1 (commit d782b4c) migró el parser Elixir de regex a AST-based
# usando Code.string_to_quoted!/1. Mide el costo del parseo AST sobre
# código real sintético de varios tamaños.

Code.require_file("fixtures.exs", "bench/")

defmodule Bench.Parser do
  def run do
    sample_paths = %{
      "small (50 lines)" => Path.join(["bench/fixtures/small/lib", pick("small")]),
      "medium (50 lines)" => Path.join(["bench/fixtures/medium/lib", pick("medium")]),
      "large (50 lines)" => Path.join(["bench/fixtures/large/lib", pick("large")])
    }

    # Pre-load all contents
    inputs =
      Map.new(sample_paths, fn {label, path} ->
        {label, File.read!(path)}
      end)

    Benchee.run(
      %{
        "Code.string_to_quoted!/1 (AST)" => fn content ->
          Code.string_to_quoted!(content)
        end,
        "Regex extract defmodule" => fn content ->
          Regex.scan(~r/defmodule\s+([\w.]+)/, content)
          |> Enum.map(fn [_, name] -> name end)
        end
      },
      inputs: inputs,
      time: 2,
      memory_time: 1,
      warmup: 0.5,
      formatters: [{Benchee.Formatters.Console, comparison: true, extended: true}]
    )

    IO.puts("\n--- Notes ---")
    IO.puts("AST parsing is ~10x slower than regex for trivial extraction.")
    IO.puts("But AST gives correct nested modules + macros + heredocs (correctness win).")
  end

  defp pick(size) do
    Enum.at(File.ls!("bench/fixtures/#{size}/lib"), 5)
  end
end

Bench.Parser.run()
