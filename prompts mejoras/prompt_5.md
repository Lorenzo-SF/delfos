📦 PROMPT 5: Hardening en Producción, Observabilidad & Export/Import
Contexto: Delfos funciona en dev/test, pero falta testing riguroso, métricas, caché, exportación de índices, y documentación de arquitectura. No es listo para CI/CD o uso compartido.
Objetivo: Añadir Dialyzer estricto, property-based tests, benchmark suite, ETS cache, export/import de índices, métricas Telemetry, y documentación técnica completa.
Requisitos Técnicos:
dialyzer con :warn_missing_spec y :warn_unmatched_returns
Tests con StreamData para parsers, retrievers, chunker
Delfos.Cache con ETS para queries frecuentes + TTL 5m
delfos export → tar.gz con schema, data, embeddings
delfos import → restaura índice sin re-scan
:telemetry para [:delfos, :search, :latency], [:delfos, :embed, :batch_size], etc.
Documentación: SPEC.md, ARCHITECTURE.md, DEPLOYMENT.md, LOCAL_LLM_GUIDE.md
Pasos de Implementación:
# 1. Telemetry setup
defmodule Delfos.Telemetry do
  def setup do
    :telemetry.attach("delfos-search", [:delfos, :search, :stop], &__MODULE__.handle_search/4, nil)
  end
  def handle_search(_event, measurements, metadata, _config) do
    Logger.info("Search took #{measurements.duration}ms for #{metadata.query}")
  end
end

# 2. ETS Cache
defmodule Delfos.Cache do
  @table :delfos_cache
  def start_link, do: :ets.new(@table, [:set, :named_table, :public])
  def get(key), do: :ets.lookup(@table, key) |> List.first() |> then(&elem(&1 || :nil, 1))
  def put(key, val, ttl \\ 300_000) do
    :ets.insert(@table, {key, val})
    Process.send_after(self(), {:evict, key}, ttl)
  end
end

# 3. Export/Import CLI
defmodule Delfos.CLI.Commands.Export do
  def run(_args) do
    # pg_dump --schema-only + SELECT * FROM symbols/chunks/relationships TO CSV
    # tar cf delfos-index.tar.gz schema.sql symbols.csv chunks.csv relationships.csv metadata.json
  end
end
Criterios de Aceptación:
mix dialyzer pasa 0 warnings
mix test --cover ≥ 85% coverage, 0 flaky tests
delfos export genera archivo < 500MB para 50k símbolos
delfos import restaura índice funcional en < 10s
Dashboard Telemetry muestra latencia p95 < 150ms
SPEC.md documenta contratos de módulos, LOCAL_LLM_GUIDE.md pasos exactos para llama-server
Dependencias: :dialyxir, :stream_data, :telemetry, :benchee, :ex_doc

