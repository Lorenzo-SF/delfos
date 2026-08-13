# Bench suite: corre todos los benchmarks y reporta.
#
# Uso:
#   mix run bench/run.exs [scanner|chunker|parser|manager|all]
#
# Por defecto corre todos. Cada uno tarda 30-60s.

args = System.argv()
target = case args do
  [] -> :all
  [t] -> String.to_atom(t)
  _ -> :all
}

benches = [
  {:scanner, "bench/scanner.exs"},
  {:parser, "bench/parser.exs"},
  {:chunker, "bench/chunker.exs"},
  {:manager, "bench/config_manager.exs"}
]

to_run = case target do
  :all -> benches
  t -> Enum.filter(benches, fn {name, _} -> name == t end)
end

if Enum.empty?(to_run) do
  IO.puts("No matching benchmark for: #{target}")
  IO.puts("Available: #{Enum.map_join(benches, ", ", fn {n, _} -> Atom.to_string(n) end)}")
  System.halt(1)
end

Enum.each(to_run, fn {name, script} ->
  IO.puts("\n========================================")
  IO.puts("  Running: #{name}")
  IO.puts("========================================")
  Code.eval_file(script)
end)
