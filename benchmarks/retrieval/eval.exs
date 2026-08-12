# Eval script: corre el eval set contra una retrieval function dummy.
# En producción, conectar con Delfos.Retrieval.HybridSearch real.

Code.require_file("../../lib/delfos/benchmarks/retrieval.ex", File.cwd!())

# Mock retrieval: simula que la búsqueda devuelve siempre un hit
# en la primera posición (precision@5 = 1.0, MRR = 1.0).
# Esto es solo para verificar que el eval corre sin errores.
mock_retrieval = fn _query ->
  [
    %{name: "Auth.authenticate/2", qualified_name: "Auth.authenticate/2"},
    %{name: "Other", qualified_name: "Other.thing/0"},
    %{name: "Unrelated", qualified_name: "Unrelated.module"}
  ]
end

result = Delfos.Benchmarks.Retrieval.run_eval(mock_retrieval, 5)
Delfos.Benchmarks.Retrieval.print_summary(result)
