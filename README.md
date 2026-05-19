# Delfos

Base de conocimiento estructurada y consultable para proyectos de software.

## Qué es

Delfos indexa un proyecto de software (código fuente, git history, dependencias)
en PostgreSQL con pgvector y expone una CLI para búsqueda híbrida, auditoría
de deuda técnica y generación de contexto para agentes de IA.

No es un RAG genérico. Entiende funciones, módulos, tests, migraciones y
el grafo de dependencias entre ellos.

## Prerequisitos

- Elixir 1.16+
- PostgreSQL 16+ con extensión pgvector
- Servidor de embeddings (nomic-embed-text o BGE-M3 vía llama-server)
- Opcional: gpt-oss-20b para summaries y explain

## Instalación

```bash
# 1. Clonar e instalar dependencias
git clone <repo>
cd delfos
mix deps.get

# 2. Crear base de datos
mix ecto.create && mix ecto.migrate

# 3. Compilar CLI
mix escript.build
```

## Configuración

Variables de entorno:

```bash
export DATABASE_URL="postgresql://localhost/delfos"
export EMBED_URL="http://127.0.0.1:9998"   # servidor de embeddings
export EMBED_MODEL="nomic-embed-text"
export EMBED_DIM="768"
export LLAMA_URL="http://127.0.0.1:9999"   # gpt-oss-20b
export LLM_MODEL="gpt-oss-20b"
export API_KEY="sk-local-dev-key"
```

## Uso

```bash
# Indexar un proyecto
./delfos init /ruta/a/tu/proyecto

# Búsqueda semántica
./delfos query "autenticación JWT"
./delfos query "manejo de errores" --kind function -n 10

# Auditoría de deuda técnica
./delfos audit

# Explicar un módulo o función
./delfos explain MyApp.Auth

# Grafo de dependencias
./delfos graph callers MyApp.Auth.validate_token/1
./delfos graph impact MyApp.Billing.PaymentProcessor.charge/2

# Generar contexto para agentes (AGENTS.md, CLAUDE.md)
./delfos context

# Resúmenes jerárquicos via LLM
./delfos summarize

# Modo watch (reindexación incremental en tiempo real)
./delfos watch

# Diagnóstico del sistema
./delfos doctor
./delfos status
```

## Arquitectura

```
lib/delfos/
  llm/client.ex           HTTP client para LLM y embeddings
  parsers/                Parsers por lenguaje (Elixir, TS, Python)
  indexer/scanner.ex      Scan con Flow (paralelo)
  indexer/file_processor.ex  Parseo + embedding + DB por archivo
  indexer/chunker.ex      Chunks semánticos (una unidad = una función)
  indexer/graph_builder.ex   Grafo de dependencias
  retrieval/              Búsqueda híbrida: vector + BM25 + grafo
  analysis/               Churn git, coupling, ciclos, deuda
  cli/                    Comandos de la CLI
```

## Modelos de embeddings soportados

| Modelo | Dim | RAM | Calidad código | Multilingüe |
|--------|-----|-----|---------------|-------------|
| nomic-embed-text-v1.5 | 768 | ~90 MB | buena | limitado |
| BGE-M3 | 1024 | ~600 MB | muy buena | sí |

Para BGE-M3: `EMBED_DIM=1024` y cambiar `vector(768)` a `vector(1024)` en las migraciones.
