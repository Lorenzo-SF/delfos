📦 PROMPT 1: Stack Local LLM & Pipeline de Embeddings Optimizado
Contexto: Delfos actualmente depende de servidores externos y no maneja fallos de red, validación de dimensiones ni fallback offline. El objetivo es hacerlo 100% local, resiliente y optimizado para CPU.
Objetivo: Integrar modelos GGUF locales vía llama-server, optimizar el batch de embeddings, añadir validación estricta de dimensiones, retry con backoff exponencial y fallback degradado a BM25+Grafo cuando el LLM no responda.
Requisitos Técnicos:
Reemplazar Delfos.LLM.Client por un adapter pattern con Delfos.LLM.Adapter (behaviour) y Delfos.LLM.LocalAdapter.
Validar dimensión de embedding en runtime antes de persistir. Si length(vec) != config[:dim], log error + marcar nil + alertar en doctor.
Implementar retry con backoff exponencial (Req soporta nativamente retry: [max_retries: 3, delay: fn n -> 100 * :math.pow(2, n) end]).
Si embed_batch/2 falla >30% de items, activar modo degradado: HybridSearch ignora VectorSearch y usa solo BM25+Grafo.
Configurar llama-server flags óptimos: --threads 4, --batch-size 64, --no-mmap (evita swapping en disco para embeddings).
Pasos de Implementación:

# 1. Behaviour

defmodule Delfos.LLM.Adapter do
@callback embed(text :: String.t()) :: {:ok, list(float)} | {:error, term()}
@callback embed_batch(texts :: [String.t()]) :: [{:ok, list(float)} | {:error, term()}]
@callback chat(messages :: list()) :: {:ok, String.t()} | {:error, term()}
end

# 2. LocalAdapter con Req + validación

defmodule Delfos.LLM.LocalAdapter do
@behaviour Delfos.LLM.Adapter
def embed(text) do
cfg = Application.get_env(:delfos, :embedding)
case Req.post("#{cfg[:url]}/v1/embeddings",
auth: {:bearer, cfg[:api_key]},
json: %{model: cfg[:model], input: String.slice(text, 0, cfg[:max_chars] || 4000)},
retry: [max_retries: 3, delay: fn n -> 100 * :math.pow(2, n) end],
receive_timeout: cfg[:timeout_ms]
) do
{:ok, %{status: 200, body: %{"data" => [%{"embedding" => vec}]}}} ->
if length(vec) == cfg[:dim], do: {:ok, vec}, else: {:error, :dim_mismatch}
other -> {:error, :http_failure}
end
end

def embed*batch(texts) do
cfg = Application.get_env(:delfos, :embedding)
texts
|> Enum.chunk_every(cfg[:batch_size] || 32)
|> Enum.flat_map(fn batch ->
case Req.post("#{cfg[:url]}/v1/embeddings", ...) do
{:ok, %{status: 200, body: %{"data" => data}}} ->
Enum.map(data, fn %{"embedding" => v} -> {:ok, v} end)
* -> Enum.map(batch, fn \_ -> {:error, :http_failure} end)
end
end)
end

# chat/1 implementado análogamente

end

Criterios de Aceptación:
delfos doctor muestra ✓ Embedding: dim=768, modelo=nomic-embed-text-v1.5
Si llama-server embedding cae, delfos query "autenticación" devuelve resultados vía BM25+Grafo sin crash
Tests de propiedad validan que embed_batch/1 mantiene orden y maneja nil en fallos
Memoria pico < 150MB durante batch de 1000 símbolos
Dependencias: :req ≥ 0.5, :telemetry (para métricas de latencia), llama-server ejecutable en PATH
