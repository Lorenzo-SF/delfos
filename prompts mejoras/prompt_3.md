📦 PROMPT 3: Retrieval Semántico Híbrido & Síntesis de Dispatch Dinámico
Contexto: HybridSearch combina vector, BM25 y grafo, pero ignora pesos en RRF. No resuelve callbacks, eventos, DI ni rutas dinámicas. El grafo es estático y pierde llamadas implícitas.
Objetivo: Implementar RRF ponderado, añadir synthesizers para dispatch dinámico, mejorar índices pgvector, y añadir reranker ligero opcional.
Requisitos Técnicos:
Modificar Reranker.merge/2 para aplicar pesos: contribution = weight * (1.0 / (@rrf_k + rank))
Crear Delfos.Resolution.Synthesizers:
CallbackSynthesizer: emitter.on/3 → emitter.emit/2 (match por nombre evento)
RouteSynthesizer: @router.get → handler (Phoenix/NestJS/FastAPI)
DISynthesizer: interface → impl (Spring/NestJS providers)
Marcar edges sintetizados con provenance: :heuristic y metadata {registered_at, framework}
Optimizar pgvector: cambiar ivfflat a hnsw si lists > 1000, añadir WHERE not is_null(embedding) en queries
(Opcional) Cross-encoder reranker local: Qwen2.5-Coder-0.5B para rerank top-20 → top-5
Pasos de Implementación:
# 1. RRF ponderado
defmodule Delfos.Retrieval.Reranker do
  @rrf_k 60
  def merge(sources, k: k) do
    rrf_scores =
      Enum.reduce(sources, %{}, fn {_name, {results, weight}}, acc ->
        results
        |> Enum.with_index(1)
        |> Enum.reduce(acc, fn {result, rank}, inner_acc ->
          contribution = weight / (@rrf_k + rank)
          Map.update(inner_acc, result.id, {contribution, result}, fn {score, r} ->
            {score + contribution, r}
          end)
        end)
      end)
    # ... resto igual
  end
end

# 2. Callback synthesizer
defmodule Delfos.Resolution.CallbackSynthesizer do
  def synthesize(symbols, edges) do
    registrations = Enum.filter(symbols, & &1.kind == "event_registration")
    emissions = Enum.filter(symbols, & &1.kind == "event_emission")
    Enum.flat_map(registrations, fn reg ->
      match_events = Enum.filter(emissions, & String.contains?(&1.signature, reg.event_name))
      Enum.map(match_events, fn em ->
        %{from_id: em.id, to_id: reg.handler_id, kind: "calls", provenance: :heuristic, metadata: %{framework: "phoenix", event: reg.event_name}}
      end)
    end)
  end
end
Criterios de Aceptación:
delfos query "auth callback" devuelve handlers registrados vía Plug.Conn.register_before_send
Reranker.merge con vector: {res, 0.6}, bm25: {res, 0.4} prioriza vector correctamente
Grafo incluye edges :provenance => :heuristic visibles en delfos explain
Latencia HybridSearch.search/3 < 200ms para 50k símbolos
pgvector hnsw activo si count > 5000
Dependencias: pgvector ≥ 0.3, :telemetry para métricas de retriever, :nimble_options para config