# Delfos — Especificación Técnica Completa
## Versión 0.5 | Estado: Referencia Canónica

---

## 1. Definición Orgánica

Delfos es una base de conocimiento semántico local para proyectos de software.
Su propósito es indexar un proyecto de código — o varios — en una estructura
consultable que combina embeddings vectoriales, búsqueda textual BM25 y un grafo
de dependencias, generando sobre ellos resúmenes mediante LLM y exponiendo todo
vía servidor MCP y CLI para que agentes de IA (Claude Code, Cursor, OpenCode,
Aider, Codex, Zed...) puedan trabajar con contexto real y preciso del código en
lugar de leer archivos a ciegas.

**Delfos no es un agente.** Es una capa de infraestructura de conocimiento.
Su cliente primario es un agente, no un humano. Cada decisión de diseño —
formato de respuesta, estructura de datos, API MCP — se toma con ese cliente
en mente.

### Principios de diseño

1. **Precisión sobre exhaustividad.** Mejor devolver 5 símbolos relevantes que
   50 ruido. La búsqueda híbrida con RRF existe para esto.

2. **Densidad de información.** Las respuestas a agentes deben ser compactas:
   máxima semántica por token. Nada de Markdown decorativo ni frases de relleno.

3. **Resiliencia.** Si el servidor de embeddings no está, la búsqueda BM25 sigue
   funcionando. Si tree-sitter no compiló, el parser regex continúa. Cada capa
   degrada con gracia.

4. **Configurabilidad sin fricción.** Un archivo TOML en `~/.config/delfos/`
   controla todo: provider de LLM, embeddings, pesos de búsqueda. El CLI permite
   cambiarlo sin editar ficheros.

5. **Integración trivial.** `delfos integrate` configura todos los agentes
   conocidos en un solo comando. `delfos serve --mcp` expone el servidor MCP.

6. **Tiempo real.** El índice se mantiene actualizado automáticamente. Cuando el
   agente consulta tras editar un archivo, los datos son frescos. No hay que
   ejecutar `delfos scan` manualmente durante el trabajo diario.

7. **CLI de primera clase.** El CLI usa Alaja para output rico y coherente:
   tablas, barras de progreso animadas, colores semánticos e iconos. La
   experiencia humana del CLI es tan cuidada como la API MCP para agentes.

---

## 2. Arquitectura General

```
┌─────────────────────────────────────────────────────────────────┐
│                        DELFOS                                    │
│                                                                  │
│  CLI (delfos <cmd>)                MCP Server (stdio)           │
│        │                                  │                      │
│        └──────────────┬───────────────────┘                      │
│                       │                                          │
│              ┌────────▼────────┐                                 │
│              │   Application   │  OTP supervision tree           │
│              │  Delfos.Repo    │  PostgreSQL + pgvector          │
│              │  Task.Supervisor│                                  │
│              │  Watcher (opt.) │  file_system watcher            │
│              └────────┬────────┘                                  │
│                       │                                          │
│     ┌─────────────────┼──────────────────────┐                   │
│     │                 │                      │                   │
│  INDEXER          RETRIEVAL              ANALYSIS                │
│  Scanner          HybridSearch           CouplingAnalyzer        │
│  FileProcessor    VectorSearch           ChurnAnalyzer           │
│  Chunker          BM25Search             GraphBuilder            │
│  GraphBuilder     GraphSearch            (Tarjan SCC)            │
│  Watcher          Reranker (RRF)                                 │
│     │                                                            │
│  PARSERS                                                         │
│  Dispatcher → TreeSitter NIF (Rust) → 19 lenguajes AST          │
│            → DartParser / HCLParser / YAMLParser                 │
│            → GenericParser (regex fallback)                      │
│                                                                  │
│  LLM                              CONFIG                         │
│  Client (local/openai/anthropic)  Manager (TOML)                │
│  FrameworkContext                 Arrea.Parallel                 │
│  (prompt enrichment)              Apero.Doctor                   │
└─────────────────────────────────────────────────────────────────┘
```

### Árbol de supervisión OTP

```
Delfos.Supervisor (one_for_one)
├── Delfos.Repo
├── Task.Supervisor            (name: Delfos.TaskSupervisor)
├── Delfos.MCP.IndexBroadcaster  (siempre activo; no-op en modo :cli sin clientes)
└── Delfos.Indexer.Watcher     (siempre en :mcp; en :cli solo si watch: true)
```

**Modo MCP — comportamiento crítico:**
- Logger redirigido a `:standard_error` (stdout es el canal JSON-RPC)
- Nivel Logger reducido a `:warning` para minimizar ruido en stderr
- Watcher arranca con `mode: :mcp` — logs a stderr, notifica a IndexBroadcaster
- MCP Server registra su PID en IndexBroadcaster al arrancar
- Al re-indexar un lote, IndexBroadcaster envía `notifications/tools/list_changed`

---

## 3. Modelo de Datos

### 3.1 Schemas Ecto

#### `projects`
```
id             uuid PK
name           string NOT NULL
path           string NOT NULL UNIQUE
primary_stack  string          -- "elixir" | "typescript" | etc.
all_stacks     string[]        -- todos los lenguajes detectados
git_remote     string
git_branch     string
last_commit    string
last_scanned   utc_datetime
config         map
inserted_at / updated_at
```

#### `files`
```
id             uuid PK
project_id     uuid FK → projects
path           string NOT NULL  -- relativa a project.path
language       string
size_bytes     bigint
line_count     integer
last_modified  naive_datetime
last_indexed   naive_datetime
content_hash   string           -- SHA256, para detección de cambios
git_churn      integer          -- número de commits que tocaron el archivo
git_authors    string[]         -- autores únicos del archivo
risk_score     float            -- churn * log(authors+1)
inserted_at / updated_at
UNIQUE(project_id, path)
```

#### `symbols`
```
id             uuid PK
file_id        uuid FK → files
project_id     uuid FK → projects
name           string NOT NULL
qualified_name string           -- Módulo.función/aridad o ClassName.method
kind           string NOT NULL  -- ver §3.2
visibility     string           -- "public" | "private" | "protected"
line_start     integer
line_end       integer
signature      string           -- @spec, firma TypeScript, etc.
docstring      string           -- @doc, JSDoc, docstring Python
content        string           -- código fuente del símbolo
language       string
metadata       map              -- datos específicos del parser
embedding      vector(1024)     -- embedding BGE-M3 del texto enriquecido
summary        string           -- resumen LLM generado por delfos summarize
summary_hash   string           -- hash del content en el momento del resumen
inserted_at / updated_at
```

**Índices en symbols:**
- `ivfflat (embedding vector_cosine_ops) lists=100`
- `gin(to_tsvector('simple', name || qualified_name || content))`
- `(project_id, kind)`
- `(project_id, qualified_name)`

#### `chunks`
```
id             uuid PK
file_id        uuid FK → files
project_id     uuid FK → projects
symbol_id      uuid FK → symbols  (opcional, si el chunk pertenece a un símbolo)
content        text NOT NULL
line_start     integer
line_end       integer
chunk_index    integer
token_count    integer
embedding      vector(1024)
inserted_at / updated_at
```

**Índices:** ivfflat en embedding, gin FTS en content.

#### `summaries`
```
id             uuid PK
project_id     uuid FK → projects
file_id        uuid FK → files   (opcional)
symbol_id      uuid FK → symbols (opcional)
level          integer            -- 3=archivo, 4=símbolo
scope          string NOT NULL    -- ruta del archivo o qualified_name
content        text NOT NULL
content_hash   string
embedding      vector(1024)
model_used     string
generated_at   utc_datetime
inserted_at / updated_at
UNIQUE(project_id, level, scope)
```

#### `relationships`
```
id             uuid PK
project_id     uuid FK → projects
from_id        uuid FK → symbols
to_id          uuid FK → symbols
kind           string NOT NULL    -- "imports" | "calls" | "inherits" | "uses"
weight         float DEFAULT 1.0
metadata       map
inserted_at / updated_at
UNIQUE(from_id, to_id, kind)
```

**Índices:** `(project_id, from_id, kind)`, `(project_id, to_id, kind)`

#### `file_metrics`
```
id                  uuid PK
file_id             uuid FK → files UNIQUE
project_id          uuid FK → projects
afferent_coupling   integer   -- Ca: cuántos dependen de este archivo
efferent_coupling   integer   -- Ce: cuántos usa este archivo
instability         float     -- Ce/(Ca+Ce): 0=estable, 1=inestable
in_cycle            boolean   -- detectado por Tarjan SCC
test_coverage_est   float
todo_count          integer
complexity_score    float
debt_score          float
inserted_at / updated_at
```

#### `agent_sessions`
```
id             uuid PK
project_id     uuid FK → projects
query          text
retrieved_ids  uuid[]
was_useful     boolean
metadata       map
inserted_at / updated_at
```

### 3.2 Kinds de símbolos válidos

```
function   module    class     macro      struct    type
interface  enum      trait     impl       decorator callback
use        behaviour endpoint  test       schema    migration
constant   resource  variable  job        workflow  service
```

---

## 4. Pipeline de Indexado

### 4.1 Flujo completo

```
delfos scan --full
    │
    ├─ ChurnAnalyzer.analyze(project)     [git log, riesgo por archivo]
    │
    ├─ Scanner.find_source_files(path)    [filtro extensión + ignore_dirs]
    │
    ├─ Arrea.Parallel.run_sync(funs, workers: 4)
    │       └── FileProcessor.process_file(path, content, project)
    │               ├─ Dispatcher.parse(path, content)
    │               │       ├─ TreeSitter NIF (AST real, 19 lenguajes)
    │               │       ├─ DartParser / HCLParser / YAMLParser
    │               │       └─ GenericParser (regex fallback)
    │               ├─ upsert_file(...)
    │               ├─ process_symbols(...)  [embed_batch en una sola llamada HTTP]
    │               └─ process_chunks(...)   [embed_batch]
    │
    ├─ GraphBuilder.build(project)
    │       ├─ mix xref (Elixir) / regex imports (TS/Python/Elixir fallback)
    │       ├─ persist_edges(...)
    │       └─ detect_and_mark_cycles(project)  [Tarjan SCC]
    │
    └─ CouplingAnalyzer.analyze(project)
            [Ca, Ce, instability, debt_score, todo_count, complexity_score]
```

### 4.2 Texto de embedding por símbolo

```elixir
[kind, qualified_name, signature, docstring, content[0..600]]
|> Enum.reject(&is_nil/1)
|> Enum.join(" ")
```

El enriquecimiento combina tipo, nombre completo, firma, documentación y
fragmento de código para que el embedding capture semántica funcional, no solo
léxica.

### 4.3 Chunking

Estrategia: `chunk_by_size` con `max_tokens: 512`. Usa `:binary.part/3` en lugar
de `String.graphemes` para eficiencia. Garantiza UTF-8 válido en cada chunk.
Los chunks se rehacen completamente en cada scan del archivo (delete + insert).

### 4.4 Detección incremental

En modo incremental (`delfos scan` sin `--full`):
1. Carga el mapa `{path => content_hash}` de la DB en una sola query.
2. Por cada archivo en disco, calcula SHA256 del contenido.
3. Solo procesa los que difieren.

`FileProcessor.compute_hash/1` es público para que Scanner lo reutilice
(el hash se calcula una sola vez, no dos veces).

### 4.5 Indexado en tiempo real (modo MCP y watch)

El `Watcher` arranca siempre en modo MCP y opcionalmente en CLI (`delfos watch`).

```
Archivo guardado por el usuario o agente
    │
    ↓ 1500ms debounce por archivo
Watcher detecta :modified/:created
    │
    ↓ Task.Supervisor.start_child (no bloquea el Watcher)
FileProcessor.process_file(path, content, project)
    │
    ↓ ~2-5s en GPU (parseo AST + embed batch)
DB actualizada con símbolos y embeddings frescos
    │
    ↓ GenServer.cast → IndexBroadcaster
IndexBroadcaster acumula paths (ventana de 3s para batching)
    │
    ↓ flush_batch (una notificación por lote, no por archivo)
MCP Server recibe {:mcp_notification, json}
    │
    ↓ stdout
{"jsonrpc":"2.0","method":"notifications/tools/list_changed",
 "params":{"_meta":{"updated_paths":["lib/x.ex"], "timestamp":"..."}}}
    │
    ↓
Agente invalida caché → próxima tool call = datos frescos
```

**Latencia total:** 5-10 segundos en GPU, 15-30 segundos en CPU pura.
**Batching:** si el agente edita 10 archivos en ráfaga, el agente recibe
una sola notificación, no 10.

---

## 5. Sistema de Parseo

### 5.1 Árbol de decisión del Dispatcher

```
Dispatcher.parse(path, content)
    │
    ├─ ext in [".dart"]            → DartParser
    ├─ ext in [".tf", ".hcl"]     → HCLParser
    ├─ ext in [".yaml", ".yml"]   → YAMLParser
    ├─ TreeSitter.supported?(lang) → TreeSitter.parse(path, content, lang)
    │                                   └─ NIF ok → símbolos AST reales
    │                                   └─ NIF falla → GenericParser (fallback)
    └─ else                        → GenericParser
```

El resultado siempre incluye `language` en el mapa devuelto.

### 5.2 TreeSitter NIF (Rust + Rustler)

**Lenguajes con soporte AST completo:**
Elixir, TypeScript, TSX, JavaScript, Python, Rust, Go, Java, Kotlin, C#,
C, C++, PHP, Ruby, Swift, Dart, Scala, Lua, Bash

**Cómo funciona:**
- NIF compilado en Rust vía Rustler (`DirtyCpu` scheduler para no bloquear).
- Para cada lenguaje, el código Rust usa tree-sitter con el grammar correspondiente.
- Extrae símbolos recursivamente desde el AST con contexto de padre (para
  qualified_name de métodos dentro de clases).
- Devuelve lista de mapas con: name, qualified_name, kind, line_start, line_end,
  visibility, signature.
- Si el NIF no carga (sin Rust instalado, CI sin compilación), el wrapper Elixir
  captura el error y delega a GenericParser. `delfos doctor` reporta el estado.

**Entrypoints del NIF:**
```
parse_symbols(language :: binary, source :: binary)
  → {:ok, [symbol_map]} | {:error, reason}

supported_languages()
  → [binary]
```

### 5.3 Parsers especializados

**DartParser** — detecta:
- `class` con herencia (StatelessWidget, StatefulWidget, State<>, BLoC, Cubit,
  ChangeNotifier, Notifier)
- `mixin`, `extension`, `enum`, `typedef`
- Funciones y métodos (sync y async, factory constructors)
- Metadata en `%{widget_type: ..., framework: "flutter"}` para FrameworkContext

**HCLParser** — detecta:
- `resource "tipo" "nombre"` → qualified_name: `tipo.nombre`
- `module`, `variable`, `output`, `provider`, `data`, `locals`, `terraform`
- El tipo de recurso (aws_s3_bucket, etc.) va en metadata para búsqueda semántica

**YAMLParser** — detecta por tipo de documento:
- Kubernetes: `kind + metadata.name`
- GitHub Actions: nombre de workflow + jobs
- GitLab CI: stages + jobs
- Docker Compose: services, volumes, networks
- Helm values: top-level keys
- YAML genérico: top-level keys con sub-estructura

### 5.4 GenericParser (regex)

Patrones para: Rust (fn, struct, enum, trait, impl), Go (func, type struct,
type interface), Java/Kotlin (class, fun, method), C# (class, method), Ruby
(class, def), PHP (class, function), Erlang (funciones), Shell (funciones),
y cualquier otro lenguaje no soportado por los anteriores.

Visibilidad: `pub` para Rust, mayúscula inicial para Go, `_` prefijo para Python.

---

## 6. Módulo LLM

### 6.1 Client multi-proveedor

`Delfos.LLM.Client` soporta tres proveedores:

| Provider | Chat endpoint | Embeddings |
|----------|---------------|------------|
| `:local` | `/v1/chat/completions` (OpenAI-compat) | `/v1/embeddings` |
| `:openai` | `/v1/chat/completions` | `/v1/embeddings` |
| `:anthropic` | `/v1/messages` (Anthropic API) | ❌ No soportado |

Si el provider de embeddings es `:anthropic`, Delfos avisa en `doctor` y no
intenta generar embeddings.

**Enrutamiento por caso de uso:**

```
chat(messages, use_case: :summarize)  → modelo rápido (Coder/Phi4), max_tokens: 180
chat(messages, use_case: :explain)    → thinker si configurado,    max_tokens: 600
chat(messages, use_case: :query)      → thinker si configurado,    max_tokens: 512
```

Si quieres separar el endpoint de chat del de summarize, configura
una sección `[summarize]` separada (v2.5.0: `[summarize]` es ahora
la sección canónica para summarise; la sección `[llm]` se mantiene
para backwards-compat). Summarize y chat usan el mismo endpoint por
defecto (puerto 9999 del wrapper `llama-run gpt-oss`).

**Diferencia clave con Anthropic:** el sistema usa `/v1/messages` con campo
`system` separado, sin `chat_template_kwargs`. Los mensajes con `role: "system"`
se extraen y se pasan como campo `system` de primer nivel.

**embed_batch:** envía hasta `batch_size` textos (default 48) en una sola
llamada HTTP. Los textos se truncan a 8000 caracteres antes del envío. La función
devuelve una lista en el mismo orden, con `nil` para los que fallan.

### 6.2 FrameworkContext

Detecta el framework usado por un símbolo para enriquecer los prompts LLM.
Tres capas de detección en orden:
1. `metadata["framework"]` — si el parser lo detectó explícitamente
2. Contenido del símbolo — patrones de imports/decoradores/macros
3. Ficheros raíz del proyecto — mix.exs, package.json, Cargo.toml, etc.

**Lenguajes con detección de framework:**
- Elixir: Phoenix (LiveView/Controller/Channel/Router), Ecto, GenServer,
  Broadway, Oban, Absinthe
- TypeScript/JS: Angular, NestJS, React (hooks/class), Vue 2/3, Redux,
  Express, Fastify, Prisma, Next.js, Nuxt.js
- Python: Flask, FastAPI, Django (ORM/views/DRF/admin), SQLAlchemy, Celery
- Ruby: Rails (controller/model/Devise/Sidekiq)
- PHP: Laravel (controller/Eloquent/routes), Symfony
- Java: Spring MVC/Boot/Data/JPA, Android Activity/Fragment
- Kotlin: Compose, ViewModel, coroutines, Spring Boot
- Dart: Flutter (Stateless/Stateful/BLoC/Riverpod/GetX/Provider)
- Swift: SwiftUI, UIKit
- Rust: Actix-web, Axum, Rocket, Tokio, Diesel, SQLx
- Go: Gin, Fiber, net/http, GORM, gRPC
- C#: ASP.NET Core, Entity Framework, xUnit/NUnit
- Terraform, Kubernetes, GitHub Actions, Docker Compose

El resultado es una frase en inglés para incluir en el prompt:
`"using Phoenix LiveView"`, `"using React (functional component with hooks)"`, etc.

---

## 7. Sistema de Retrieval

### 7.1 Búsqueda híbrida (HybridSearch)

Combina tres motores ejecutados **en paralelo** via `Arrea.Parallel.run_sync`:

```
query
  │
  ├─ [worker 1] VectorSearch.search_with_embed(...)
  │             embed(query) → coseno pgvector
  │
  ├─ [worker 2] BM25Search.search(...)
  │             to_tsvector('simple') → ts_rank
  │
  └─ [worker 3] GraphSearch.search(...)
                BFS desde símbolo semilla encontrado por nombre
  │
  └─ Reranker.rrf_merge(...)
              Reciprocal Rank Fusion ponderado → top-K final
```

**Degradación gracia:** si el embedding falla, la respuesta sale solo de BM25.
Si BM25 falla, del vector. El grafo es siempre adicional.

**Niveles de búsqueda:**
- `nil` (default): busca en chunks
- `:symbol`: busca en símbolos (para `--level symbol`)
- `:summary`: busca en summaries (para `--level summary`)

### 7.2 Reranker (RRF)

Reciprocal Rank Fusion con k=60. Score de cada resultado:
```
score = weight_vector * 1/(60 + rank_vector)
      + weight_bm25   * 1/(60 + rank_bm25)
      + weight_graph  * 1/(60 + rank_graph)
```

Pesos por defecto: vector=0.55, bm25=0.25, graph=0.20. Configurables vía
`delfos config set retrieval vector_weight 0.6`.

RRF es scale-invariante: los scores de los tres motores no necesitan normalizarse,
lo que lo hace robusto ante cambios de modelo de embedding.

### 7.3 GraphSearch

BFS desde un símbolo semilla encontrado por nombre (ilike). Scores decrecientes
por profundidad de hop: 1→0.9, 2→0.6, 3→0.3. Usa MapSet para evitar ciclos.

### 7.4 VectorSearch

Usa `embedding <=> vector` (coseno) de pgvector. Índice ivfflat con 100 listas.
`search_with_embed` genera el embedding de la query internamente (para uso en
paralelo con Arrea sin pasarle el vector desde fuera).

### 7.5 BM25Search

`to_tsvector('simple', ...)` + `ts_rank`. El operador `'simple'` es multilingüe
(no aplica stemming específico de ningún idioma). La query se construye
tokenizando y añadiendo `:*` para prefix matching.

---

## 8. Análisis

### 8.1 ChurnAnalyzer

Parsea `git log --name-only --format=COMMIT:%an --no-merges --max-count=N`.
Por cada archivo calcula:
- `git_churn`: número de commits que lo tocaron
- `git_authors`: lista deduplicada de autores
- `risk_score`: `churn * (1 + log(num_authors))` — penaliza archivos con muchos
  autores distintos además de muchos commits

Actualiza `files.risk_score`, `files.git_churn`, `files.git_authors`.

### 8.2 CouplingAnalyzer

Para cada archivo calcula desde la tabla `relationships`:
- **Ca (afferent):** símbolos de otros archivos que llaman a símbolos de éste
- **Ce (efferent):** símbolos de éste que llaman a símbolos de otros archivos
- **instability:** `Ce / (Ca + Ce)` — 0=estable (muchos dependen de él), 1=inestable
- **todo_count:** grep de TODO|FIXME|HACK|BUG|DEBT en `symbols.content`
- **complexity_score:** `line_count / symbol_count` — proxy de densidad
- **debt_score:** `Ca + Ce + (if instability > 0.7: 5) + todo_count * 2`

Guarda en `file_metrics`. Preserva `in_cycle` si ya fue marcado por GraphBuilder.

### 8.3 GraphBuilder + Tarjan SCC

GraphBuilder construye el grafo de `relationships` desde:
- **Elixir:** `mix xref graph --format dot` → parsea el fichero `.dot`
- **TypeScript/JS:** regex de `import ... from` y `require(...)`
- **Python:** regex de `from X import` e `import X`
- **Elixir fallback:** regex de `alias/import/use`

Tras construir el grafo ejecuta **Tarjan SCC** para encontrar componentes
fuertemente conectados. Los SCCs con más de un nodo son ciclos. Marca
`file_metrics.in_cycle = true` para todos los archivos involucrados.

El Tarjan implementado es iterativo (no recursivo) para evitar stack overflow
en proyectos grandes.

---

## 9. MCP Server

### 9.1 Protocolo

Transporte: **stdio** (JSON-RPC 2.0 sobre stdin/stdout).
Versión de protocolo: `2024-11-05`.
Arranque: `delfos serve --mcp`.

En modo MCP:
- Logger redirigido a `:standard_error`, nivel `:warning`
- Watcher arranca con `mode: :mcp` (logs a stderr)
- MCP Server registra su PID en IndexBroadcaster para recibir notificaciones

El servidor declara en la respuesta `initialize`:
```json
{
  "capabilities": {
    "tools": {},
    "experimental": {
      "indexing": {"realtime": true, "notification": "notifications/tools/list_changed"}
    }
  }
}
```

### 9.2 Loop híbrido stdin + notificaciones

```elixir
# Loop principal: comprueba notificaciones antes de bloquear en stdin
receive do
  {:mcp_notification, json} ->
    if state.initialized, do: IO.puts(json)
    loop(state)
after 0 ->
  loop_stdin(state)  # IO.gets("") — bloquea hasta próximo mensaje
end
```

Las notificaciones tienen prioridad: el `receive ... after 0` las consume
antes de intentar leer stdin.

### 9.2 Herramientas expuestas

#### `delfos_search`
```
Parámetros:
  query  string  (requerido)  — texto de búsqueda
  kind   string  (opcional)   — filtrar por tipo: function|module|class|...
  level  string  (opcional)   — symbol | chunk | summary
  limit  integer (opcional)   — máximo de resultados (default: 5)

Devuelve:
  QUERY: <texto> | RESULTS: <n>
  [1] score=0.847 kind=function name=MyModule.process
      <preview del contenido, 150 chars>
  [2] ...
```

#### `delfos_symbol`
```
Parámetros:
  name  string  (requerido)  — nombre parcial o completo del símbolo

Devuelve:
  SYMBOL: Module.function/2
  KIND: function | FILE: lib/x.ex:45-89 | LANG: elixir | VIS: public
  SUMMARY: <resumen LLM 1-2 frases>
  SPEC: @spec process(Cart.t(), User.t()) :: {:ok, Tx.t()} | {:error, String.t()}
  CALLERS(3): CheckoutController.create, OrderService.retry, Admin.refund
  CALLEES(4): Stripe.charge/2, Transaction.create/1, PubSub.broadcast/3, Logger.error/1
  RISK: debt=8.2 instability=0.71 churn=34 cycle=false
  RELATED: StripeWebhook(0.87) TransactionSchema(0.82)
  CODE:
  <código fuente, hasta 800 chars>
```

#### `delfos_context`
```
Parámetros:
  task        string  (requerido)  — descripción de la tarea
  max_symbols integer (opcional)   — máximo de símbolos (default: 8)

Devuelve: lista compacta de símbolos relevantes con resúmenes y ubicaciones.
Ideal como primer llamado al empezar a trabajar en una tarea.
```

#### `delfos_callers`
```
Parámetros:
  name  string  (requerido)

Devuelve:
  CALLERS OF: Module.function/2 (N)
    CallerA.method (function) — lib/a.ex:12
    CallerB.other  (function) — lib/b.ex:78
```

#### `delfos_callees`
```
Parámetros:
  name  string  (requerido)

Devuelve: igual que callers pero en sentido inverso
```

#### `delfos_impact`
```
Parámetros:
  name   string  (requerido)
  depth  integer (opcional)  — profundidad BFS (default: 3)

Devuelve:
  IMPACT OF: Module.function | DEPTH: 3 | AFFECTED: 12
    AffectedA.method (function)
    AffectedB.other (class)
    ...
```

#### `delfos_audit`
```
Parámetros:
  file  string  (opcional)  — ruta relativa del archivo; sin parámetro = proyecto

Devuelve para proyecto:
  AUDIT: ProjectName | SCANNED: 2026-05-31T10:00:00Z
  SYMBOLS: 1247 | EMBEDDED: 98.3% | SUMMARIZED: 71.2%
  CYCLES: 3 files in dependency cycles
  HOTSPOTS (top 5 by risk):
    lib/payments.ex | risk=18.4 churn=89
    ...

Devuelve para archivo:
  AUDIT FILE: lib/payments.ex
  LANG: elixir | LINES: 342 | SIZE: 12847b
  RISK: score=18.4 churn=89 authors=4
  COUPLING: Ca=8 Ce=12 instability=0.6
  DEBT: score=29.0 todos=3 in_cycle=false
```

#### `delfos_files`
```
Parámetros:
  filter  string  (opcional)  — filtrar por lenguaje o ruta

Devuelve:
  FILES: 127 (filter: elixir)
    lib/accounts.ex [elixir] 234L
    lib/payments.ex [elixir] 342L ⚠   (⚠ si risk > 10)
    ...
```

### 9.3 Auto-allow para Claude Code

`delfos integrate claude-code` escribe en `~/.claude/settings.json`:
```json
{
  "permissions": {
    "allow": [
      "mcp__delfos__delfos_search",
      "mcp__delfos__delfos_symbol",
      "mcp__delfos__delfos_context",
      "mcp__delfos__delfos_callers",
      "mcp__delfos__delfos_callees",
      "mcp__delfos__delfos_impact",
      "mcp__delfos__delfos_audit",
      "mcp__delfos__delfos_files"
    ]
  }
}
```

---

## 10. CLI con Alaja

### 10.1 Por qué Alaja

Delfos usa Alaja — el framework CLI del ecosistema — para todo el output
interactivo. Esto proporciona:
- **DSL declarativo** con parsing, validación de tipos y help auto-generado
- **Output semántico**: `print_success/error/warning/info` con iconos consistentes
- **Tablas ricas** para query, audit, status con bordes redondeados y colores
- **AnimatedBar** para scan y summarize (barra animada con símbolo actual)
- **Box** para mensajes importantes (instrucciones post-integrate, errores críticos)
- **"Did you mean?"** para comandos desconocidos vía Jaro distance
- **GlobalOpts** `--quiet`, `--raw`, `--align` disponibles en todos los comandos

### 10.2 Definición del CLI con `use Alaja.CLI.Definition`

Todos los comandos de Delfos se declaran en `Delfos.CLI`, usando el DSL
de Alaja con `command`, `subcommand`, `flag`, `argument` y `run`. El
dispatch, parsing de args y validación de tipos y valores los gestiona
Alaja automáticamente.

Estructura completa de comandos (v2.5.0 — cambios vs v2.4.0 marcados):

```
# ── Proyecto ───────────────────────────────────────────────────────────
delfos init [path]
delfos scan [--full] [--workers N]
delfos query <text> [--kind K] [--level L] [-n N] [--format text|json]
delfos explain <name> [--fresh] [--llm-less]
delfos audit [--file path] [--with-explanation] [--llm-less]
delfos summarize [--level N] [--force]
delfos graph callers <name> [--depth N]
delfos graph callees <name> [--depth N]
delfos graph impact  <name> [--depth N]
delfos graph cycles
delfos agents <name>                             # absorbed into `explain` (v2.3.0)

# ── Configuración ──────────────────────────────────────────────────────
delfos config show
delfos config path
delfos config init
delfos config get <section> <key>
delfos config set <section> <key> <value>
delfos config preset <local|anthropic|openai|openai-large>
delfos config migrate-local                       # NEW (v2.5.0): force stale→local
delfos config setup [db|llm]                     # wizard dispatcher
delfos config models                              # model registry inspector

# ── Integración con agentes ───────────────────────────────────────────
delfos integrate [all|<agent>] [--yes] [--project path]
   # Agents: claude-code, opencode, cursor, aider, codex, zed, vscode,
   #         claude-desktop, windsurf, continue, roo-code  (v2.4.0: +5)

# ── MCP / watch ────────────────────────────────────────────────────────
delfos mcp                                        # renamed from `serve --mcp` (v2.3.0)
delfos watch                                      # removed v2.3.0 (now in MCP tree)

# ── Diagnóstico ────────────────────────────────────────────────────────
delfos doctor [--fix] [--guided] [--json]
delfos status [--stats]                           # --stats absorbs `stadistics`
delfos version

# ── Aliases removed in v2.x ────────────────────────────────────────────
# `delfos context`           — removed v2.3.0 (was a sub-command, not a top-level)
# `delfos stadistics`        — removed v2.3.0 (use `delfos status --stats`)
# `delfos config wizard`     — removed v2.3.0 (use `delfos config setup`)
# `delfos config doctor`     — removed v2.3.0 (use `delfos doctor`)
# `delfos config probe`      — removed v2.3.0 (use `delfos doctor`)
# `delfos agents <name>`     — removed v2.3.0 (use `delfos explain <name>`)
```

### 10.3 Output visual por comando

v2.5.0 introduces a layered UI built on Alaja's Cell engine. The
table below shows which Alaja component dominates each command's
output. New in v2.5.0 (vs v2.4.0): `MultiBar`, `Pulsar`, `Box`,
`Separator`, `Breadcrumbs`, `ColorWheel`, `Message`, and `Wizard`.

| Comando | Componente Alaja (v2.5.0) |
|---------|---------------------------|
| `scan` | `AnimatedBar` per-file + ETA (v2.5.0: `--full` wraps in `MultiBar`) |
| `init` | **`MultiBar`** (NEW) — one bar for "Scanning" + reserved slots for future `--with-summary` / `--with-briefing` (Fase E) |
| `mcp` | **`Pulsar`** splash (NEW) while NIF loads + the MCP server starts |
| `query` | `Table.print` Score/Kind/Name/File/Preview with cyan headers |
| `audit` | `Table.print` hotspots + `Box.print` if cycles detected |
| `doctor` | **`Box`** "Delfos Doctor" (NEW) — colour-coded rows (green ✓ / yellow ! / red ✗) + border mirrors overall health |
| `status` | **`Box`** "Delfos Project Status" (NEW) — sections separated by `Separator`; "Last scan" colour-coded by freshness via inline ANSI (green < 1h / yellow 1-24h / red > 24h) |
| `config show` | flat sections separated by **`Separator`** (NEW) |
| `summarize` | `AnimatedBar` with current symbol (will move to `MultiBar` when --with-summary lands in Fase E) |
| `integrate` | `Box.print` post-install instructions |
| `explain` | **`Box`** "Source — <name>" + LLM output (unboxed prose) + **`Box`** "Metadata — <name>" with `Separator` between sub-sections (NEW) |
| `setup llm` | unified via **`Delfos.Setup.Wizard`** (NEW) — `welcome/3` + numbered `ask/3` + `confirm_summary/1` Box |
| `graph` | `Table.print` with callers/callees/impacted |
| Errors anywhere | **`Breadcrumbs`** + coloured text + optional **`Hint` Box** (NEW) via `Delfos.CLI.Errors` |

**Components in use by v2.5.0** (out of 13 available in Alaja 0.5+):

  ✅ `Header`, `AnimatedBar`, `Pulsar`, `MultiBar`, `Box`, `Separator`,
  `Breadcrumbs`, `ColorWheel` (palette), `Message`, `Table`, `Wizard`
  wrapper, `Progress` (legacy)

  ⏳ Not yet used (planned v2.6+): `Bar`, `Json`

**Note:** The MCP Server does NOT use Alaja. Its responses are pure
JSON-RPC over stdout. Alaja is only used in the interactive CLI.

---

## 11. Configuración Global

### 11.1 Fichero `~/.config/delfos/delfos.conf`

Formato TOML. Se crea automáticamente con defaults al primer uso. Estructura:

```toml
[embedding]
provider   = "local"              # local | openai | anthropic
url        = "http://127.0.0.1:9998"
model      = "bge-m3"
api_key    = "sk-local-dev"
dim        = 1024
batch_size = 48
timeout_ms = 25000

[llm]
provider             = "local"   # local | openai | anthropic
url                  = "http://127.0.0.1:8080"
model                = "Phi-4-mini-instruct"
api_key              = "sk-local-dev"
timeout_ms           = 45000
summarize_max_tokens = 180
explain_max_tokens   = 600
query_max_tokens     = 512
# v2.4.0+: la sección [summarize] es ahora canónica. Si está presente,
# Delfos la prefiere para summarisation; si no, cae a [llm]. La idea
# de "thinker_*" (un endpoint dedicado de razonamiento) se eliminó
# en v2.4.0 (commit ccbbedb) — la sobrecarga de mantener dos endpoints
# no compensaba el beneficio.

[retrieval]
vector_weight = 0.55
bm25_weight   = 0.25
graph_weight  = 0.20
top_k         = 25
final_k       = 7

[analysis]
churn_max_commits = 1000

[indexing]
max_chunk_tokens = 512
ignore_dirs = ["_build", "deps", "node_modules", "target", ".git",
               "dist", "coverage", "__pycache__", ".elixir_ls"]
```

### 11.2 Jerarquía de prioridad

```
1. Variables de entorno (máxima prioridad)
   EMBED_URL, EMBED_MODEL, EMBED_API_KEY, EMBED_DIM
   LLAMA_URL, LLM_MODEL, LLM_API_KEY
   THINKER_URL, THINKER_MODEL, USE_THINKER
   DELFOS_EMBED_PROVIDER, DELFOS_LLM_PROVIDER

2. ~/.config/delfos/delfos.conf

3. config/config.exs (defaults compilados)
```

### 11.3 Presets

| Preset | Proveedores | Notas |
|--------|-------------|-------|
| `local` | embedding=local, llm=local | Default, sin API keys |
| `anthropic` | llm=anthropic | Solo LLM, embedding sigue local |
| `openai` | embedding=openai (3-small, 1536d), llm=openai (gpt-4o-mini) | ⚠ cambiar dim en DB |
| `openai-large` | embedding=openai (3-large, 3072d), llm=openai (gpt-4o) | ⚠ cambiar dim en DB |

Al cambiar `dim` con el preset `openai` hay que ejecutar
`mix ecto.reset && delfos init .` o aplicar la migración 000009.

---

## 12. Modelos Recomendados

### Embedding: BGE-M3 Q4_K_M (~1.1 GB VRAM)
```
Descargar: https://huggingface.co/groonga/bge-m3-Q4_K_M-GGUF/blob/main/bge-m3-q4_k_m.gguf
Arrancar:
  llama-server -m bge-m3-q4_k_m.gguf --port 9998 --embedding \
    --threads 4 --batch-size 64 --ctx-size 2048 \
    --mlock --no-mmap --flash-attn --host 127.0.0.1
```
Ventajas: multilingüe (87 idiomas), contexto 8192 tokens, dim=1024.

### LLM: Phi-4-mini-instruct Q4_K_M (~2.8 GB VRAM)
```
Descargar: https://huggingface.co/bartowski/Phi-4-mini-instruct-GGUF/
Arrancar:
  llama-server -m Phi-4-mini-instruct-Q4_K_M.gguf --port 8080 \
    --threads 6 --batch-size 128 --ctx-size 8192 \
    --mlock --no-mmap --flash-attn --host 127.0.0.1
```

**Total con ambos: ~3.9 GB VRAM** — cabe en cualquier GPU de 6+ GB.

Alternativas más ligeras (total ~2.2 GB):
- Qwen2.5-Coder-3B Q4_K_M (~2.2 GB) — mejor en código, menor razonamiento general
- Qwen2.5-Coder-1.5B Q4_K_M (~1.1 GB) — mínimo absoluto

> **v2.3.0+:** Delfos no incluye scripts de arranque de llama-server.
> Usa el wrapper `llama-run` (ver `docs/LLM_USAGE.md` §"arranque
> rápido") o arranca los servers directamente con `llama-server
> -m <modelo> --port <port> ...`.

---

## 13. CLI — Referencia Completa (v2.5.0)

### 13.1 Estructura general

```
delfos <comando> [subcomando] [argumentos] [--flags]
```

Los comandos son módulos en `Delfos.CLI.Commands.*` con una API
estandarizada:

    help_text/0        → renderiza el bloque --help
    run_with_opts/1    → entry point preferido (recibe mapa de opts parseados)
    run/1              → legacy argv-style; los handlers convierten a opts

Alaja hace el dispatch top-level via `use Alaja.CLI.Definition`. Cada
comando expone `run_with_opts/1` que recibe los flags ya parseados —
sin re-parsear argv (commit `420c150`, Fase B1).

### 13.2 Comandos de inicialización

---

#### `delfos init [path]`

Registra un proyecto en la DB y realiza el primer scan completo.

```
Flags:
  (ninguno en v2.5.0)

Comportamiento:
1. Si path no se pasa, usa el directorio actual (File.cwd!()).
2. Detecta name (basename), primary_stack y all_stacks, git metadata.
3. ensure_llm_ready → arranca el embed server si está caído.
4. Si proyecto existe: prompt Keep/Wipe/Cancel (default Keep).
5. Si nuevo o Wipe: lanza Scan.run_with_opts(%{full: true}) envuelto
   en un Alaja.Components.MultiBar (UX1) — barra con el progreso
   "Scanning" + reserva para futuros slots (--with-summary Fase E).
6. En modo no-TTY (CI/piped), el MultiBar se omite y se usa el
   AnimatedBar legado dentro de FileProcessor.

Errores (v2.5.0 — via Delfos.CLI.Errors):
  • path no existe       → Breadcrumb [delfos › init › resolve_target_path]
                            + Hint: 'Pass an existing directory...'
  • DB no disponible     → Breadcrumb [delfos › init › ensure_booted › repo_starter]
                            + Hint: 'Run: delfos config setup db'
```

---

#### `delfos scan [--full] [--workers N]`

Re-indexa el proyecto activo (el escaneado más recientemente).

```
Flags:
  --full          Re-indexar todos los archivos, ignorando hashes
  --workers N     Número de workers paralelos (default: 4)

Opciones internas (no CLI, usadas por init.ex):
  :multi_bar       Alaja.Components.MultiBar pid  (opcional)
  :scan_task_id    atom()                          (default :scan)

Comportamiento:
1. Carga proyecto activo (order_by last_scanned desc, limit 1).
2. Scanner.find_files + find_changed_files (si !full).
3. FileProcessor.process_files_with_progress/3 — si recibe :multi_bar
   drive la barra via :on_progress callback; si no, dibuja su propio
   AnimatedBar con ETA.
4. GraphBuilder.build (Tarjan).
5. CouplingAnalyzer + ChurnAnalyzer.
6. Update last_scanned.
```

---

### 13.3 Comandos de búsqueda y consulta

---

#### `delfos query <texto> [--kind K] [--level L] [-n N] [--format text|json]`

Búsqueda híbrida (vector + BM25 + graph) en el índice.

```
Argumentos:
  texto          Texto de búsqueda (requerido)

Flags:
  --kind         Filtrar por kind: function|module|class|struct|...
  --level        Nivel: symbol|chunk|summary (default: chunk)
  -n N           Número de resultados (default: 7, del config retrieval.final_k)
  --format json  Salida JSON (útil para piping)

LLM pre-flight: :required (v2.4.0+ — LLMGuard.check("query")).
```

---

#### `delfos explain <nombre> [--fresh] [--llm-less]`

Explica un símbolo con contexto del framework, vía LLM (o estático).

```
Argumentos:
  nombre         Nombre parcial o completo (requerido)

Flags:
  --fresh        Fuerza regeneración vía LLM (skip cached summary)
  --llm-less     Salta el LLM completamente (B7); muestra solo info
                 estática + '(LLM skipped — no cached summary)' si no hay caché

Salida (v2.5.0 — UX5):
  ╭─ Source — <qualified_name> ──────╮
  │ <código resaltado>              │
  ╰────────────────────────────────╯
  {explicación LLM, sin caja}
  ╭─ Metadata — <qualified_name> ───╮
  │ Callers (n):                    │
  │   - ...                         │
  │ ──────────                      │
  │ Callees (m):                    │
  │   - ...                         │
  │ ──────────                      │
  │ Métricas del archivo:           │
  │   ...                           │
  │ ──────────                      │
  │ Semantically related chunks:    │
  │   ...                           │
  ╰────────────────────────────────╯

Errores (via Delfos.CLI.Errors):
  • No projects         → Breadcrumb + Hint: 'Run: delfos init .'
  • Symbol not found    → Breadcrumb + Hint: 'Try a partial name...'
  • LLM unreachable     → Errors.print_error + Hint Box
  • LLM call failed     → Errors.print_error + Hint Box
```

---

### 13.4 Comandos de análisis

---

#### `delfos audit [--file path] [--with-explanation] [--llm-less]`

Muestra métricas de deuda técnica.

```
Flags:
  --file path              Análisis de un archivo específico
  --with-explanation       Genera explicación LLM para los hotspots (B8)
  --llm-less               Salta LLM completamente (B7)
```

---

#### `delfos summarize [--level N] [--force]`

Genera resúmenes LLM jerárquicos (Level 3 = file, Level 4 = symbol).

---

#### `delfos graph <subcomando>`

```
callers/callees/impact <nombre> [--depth N]
cycles
```

Absorbe `delfos agents --symbol <name>` (eliminado en v2.3.0 — la
funcionalidad vive ahora dentro de `delfos explain <name>`).

---

### 13.5 Comandos de configuración

---

#### `delfos config show`

Muestra la configuración activa con API keys enmascaradas.

```
Salida (v2.5.0 — UX6): secciones separadas por Separator (── 60 chars)
  Fichero: /home/.../config.json
  ──────────────────────────────────────────
  [embedding]
    provider   = local
    url        = http://127.0.0.1:9998
    ...
  ──────────────────────────────────────────
  [llm]
    ...
```

#### `delfos config path`

Imprime la ruta del fichero JSON de configuración.

#### `delfos config init`

Crea `~/.config/delfos/config.json` con valores por defecto.
No sobreescribe si ya existe.

#### `delfos config get <section> <key>`

Lee un valor del fichero de configuración.

#### `delfos config set <section> <key> <value>`

Edita un valor. Crea la sección/clave si no existen.

#### `delfos config preset <nombre>`

Aplica un preset completo: `local`, `anthropic`, `openai`,
`openai-large`.

#### `delfos config migrate-local`  (NEW v2.5.0)

Fuerza la migración de un provider cloud stale (OpenAI/Anthropic con
URL default) a `:local`. Por defecto el auto-migrate ya es silencioso
(v2.4.0, commit `ccbbedb`); este comando es la versión explícita.

#### `delfos config setup [db|llm]`  (wizard dispatcher)

Wizard interactivo. Usa `Delfos.CLI.Commands.Setup.Wizard` (v2.5.0,
UX4) para garantizar consistencia visual con el resto del CLI.

```
delfos config setup          # top-level: elige DB/LLM/both/skip
delfos config setup db       # salta al wizard de DB
delfos config setup llm      # salta al wizard de LLM (auto-migra stale cloud)
```

#### `delfos config models`

Inspecciona el registro de modelos (`Delfos.Models.Registry`).

---

### 13.6 Comandos de integración con agentes

---

#### `delfos integrate [<agent>] [--yes] [--project path]`

Configura automáticamente la integración con agentes de IA.

```
Agentes soportados (v2.4.0: 10 totales — 5 añadidos en Fase D1+D3):
  claude-code, claude-desktop, opencode, cursor, aider, codex, zed,
  vscode, windsurf, continue, roo-code
```

### 13.7 MCP

---

#### `delfos mcp`

Arranca el servidor MCP en modo stdio.

```
v2.5.0 (5c2919c): arranque envuelto en Alaja.Components.Pulsar splash
mientras carga el NIF de tree-sitter. Da feedback visual en el cold-start
de 5-10s. Cuando el server está listo, el Pulsar se cierra.
```

---

### 13.8 Diagnóstico

---

#### `delfos doctor [--fix] [--guided] [--json]`

Diagnóstico completo (delegado a `Botica.Doctor`).

```
Salida (v2.5.0 — UX3): todo dentro de un Alaja.Components.Box
titled 'Delfos Doctor'. Border color mirrors overall health
(green / yellow / red). Cada check: ✗ (rojo) | ! (amarillo) | ✓ (verde)
```

#### `delfos status [--stats]`

Resumen del índice y proyectos.

```
Salida (v2.5.0 — UX2 + UX8): Box titled 'Delfos Project Status',
secciones separadas por Separator, 'Last scan' color-coded
(green < 1h, yellow 1-24h, red > 24h).
--stats: absorbe `delfos stadistics` (eliminado v2.3.0) — usage
snapshot + KB stats por proyecto.
```

#### `delfos version`

Imprime `Delfos v2.5.0`.

---

### 13.9 Salidas de error estándar (v2.5.0)

Todas las rutas de error siguen ahora el mismo contrato, vía
`Delfos.CLI.Errors`:

1. **Breadcrumb** — path cyan → white-leaf (UX7)
   ```
   [delfos › init › resolve_target_path]
   ```
2. **Mensaje** coloreado (rojo/amarillo/verde) vía
   `Alaja.Components.Message` (UX9)
3. **Hint Box** opcional con remediación accionable
   ```
   ╭─ Hint ──────────────────────╮
   │ Run: delfos config setup db │
   ╰─────────────────────────────╯
   ```
4. `System.halt(1)` para errores fatales (`abort/3`); `:ok` para
   warnings (`print_warning/3`).

Casos cubiertos:
- Comando desconocido → Alaja.Dispatcher's 'did you mean?'
- Sin proyectos         → Errors.print_error + Hint: 'Run: delfos init .'
- LLM no disponible    → Errors.print_error + Hint Box (start llama-run)
- Símbolo no encontrado → Errors.abort + Hint Box
- Embedding falla      → degrada a BM25 (no fatal)

---


## 14. Integración con el Ecosistema

### 14.1 Apero — Lo que Delfos usa

> **Estado (2026-07):** Apero ya **no** es dependencia runtime de Delfos.
> Las funciones que iban a vivir en Apero se migraron a otros sitios:

**`Botica.Doctor`** — base arquitectónica para `delfos doctor`.
Sustituye al antiguo (y nunca publicado) `Apero.Doctor`. Delfos construye
un mapa `%{app_name: "delfos", checks: [...]}` con estructura:
```elixir
%{
  id: :postgresql,
  name: "PostgreSQL",
  description: "Conexión DB",
  priority: 2,
  check: fn -> ... end,       # → {:ok, msg} | {:warning, msg} | {:error, msg}
  fix: fn -> ... end,         # → {:ok, msg} | :skipped | {:error, msg}
  fix_command: "texto"        # comando a mostrar al usuario para fix manual
}
```
Y llama `Botica.Doctor.run(config)`, `Botica.Doctor.fix(config)`,
`Botica.Doctor.summary(results)`.

### 14.2 Apero — Mejoras necesarias

> **Estado (2026-07):** Todas estas piezas terminaron implementadas
> fuera de Apero. A continuación el mapeo definitivo:

| Capacidad | Deseado en Apero | Implementación real |
|-----------|------------------|---------------------|
| Health de endpoints LLM/embed | `Apero.Llm.Health.check_*` | `Candil.Health.ping/3` |
| Config TOML + routing | `Apero.Llm.ConfigManager` | `Delfos.Config.Manager` (cifrado AES-256-GCM **inline** con `:crypto` de Erlang) |
| Embeddings con batching/backpressure | `Apero.Llm.Embeddings` | Candil vía `Delfos.LLM.CandilBridge.embed_batch/2` |

**`Candil.Health.ping/3`** — sustituye al antiguo
`Req.get("#{url}/health")` ad-hoc de Delfos:
```elixir
Candil.Health.ping(url, model, timeout: 5_000)
  → :ok | {:error, :timeout | :unreachable | {:http, status}}
```

**`Delfos.Config.Manager`** — lee/escribe `~/.config/delfos/delfos.conf`
como JSON cifrado con AES-256-GCM, ahora **inline** sobre `:crypto` de
Erlang (formato Base64: `iv(12) <> tag(16) <> ciphertext`). Ya no se
delega en `Apero.Crypto.Cipher`.

**`Delfos.LLM.CandilBridge`** — adaptador sobre Candil para chat,
`embed/2` y `embed_batch/2`. Implementa el rate limiting que pedía el
antiguo `Apero.Llm.Embeddings` (deseado pero nunca materializado).

### 14.3 Arrea — Lo que Delfos usa

**`Arrea.Parallel.run_sync/2`** — en dos lugares críticos:
1. `FileProcessor.process_files` — procesa N archivos con `workers: 4`
2. `HybridSearch.search` — lanza vector+BM25+grafo con `workers: 3, timeout: 15_000`

El circuit breaker de Arrea (`Arrea.CircuitBreaker`) protege implícitamente
a través del `Leader` cuando se usan commands de shell. Para funciones anónimas
(que es el caso de Delfos), `run_sync` con `Task.async_stream` maneja timeouts
y fallos sin circuit breaker explícito.

### 14.4 Arrea — Mejoras necesarias

**`run_sync` con resultados tagged:** Actualmente el resultado es una lista donde
los errores van mezclados como `{:error, %{error: reason}}`. Sería mejor que
cada posición devolviera `{:ok, value} | {:error, reason}` de forma consistente
para que `extract_result/1` en HybridSearch no necesite pattern matching frágil.

**Timeout granular por función:** Actualmente hay un timeout global para todo el
batch. Para Delfos sería útil poder pasar `[{fun1, timeout: 25_000}, {fun2, timeout: 5_000}]`.

---

### 14.5 Alaja — Mejoras necesarias para Delfos

**`MultiProgressBar`** — Para `delfos scan --full` con N archivos en paralelo,
mostrar N barras simultáneas (una por worker). Actualmente AnimatedBar solo
gestiona una barra.

**`Syntax.highlight` ampliado** — Solo soporta `:elixir`, `:json`, `:markdown`.
`delfos explain` muestra código de cualquier lenguaje. Necesario añadir al menos:
Python, TypeScript, Rust, Go, Java, Ruby.

**`Table.print` con paginación** — Para `delfos query` con muchos resultados.
`--page N` o navegación interactiva con flechas entre páginas.

---

## 15. Modelos de Datos Internos (formatos de respuesta)

### 16.1 Resultado de búsqueda

```elixir
%{
  id: binary_id,
  name: string,
  qualified_name: string,
  kind: string,
  language: string,
  file_id: binary_id,
  file_path: string,        # añadido al formatear
  line_start: integer,
  content: string,
  summary: string,
  score: float,             # score individual del motor
  combined_score: float     # score RRF final
}
```

### 16.2 Formato compacto de símbolo (para CLI y MCP)

```
SYMBOL: <qualified_name>
KIND: <kind> | FILE: <path>:<start>-<end> | LANG: <lang> | VIS: <vis>
SUMMARY: <texto 1-2 frases>
SPEC: <firma o @spec>
CALLERS(<n>): <qname1>, <qname2>, ...
CALLEES(<n>): <qname1>, <qname2>, ...
RISK: debt=<f> instability=<f> churn=<i> cycle=<bool>
RELATED: <name>(<score>) <name>(<score>) ...
CODE:
<código fuente hasta 800 chars>
```

Este formato ocupa ~150-300 tokens para un símbolo típico, frente a 800-1200
de Markdown verboso. Incluye toda la información que un agente necesita para:
- Localizar el símbolo (FILE + LINE)
- Entender su contrato (SPEC + SUMMARY)
- Planear refactoring (CALLERS + CALLEES + RISK)
- Explorar el contexto semántico (RELATED)
- Leer el código si es necesario (CODE)

---

## 16. Requisitos del Sistema

### 16.1 Tiempo de ejecución
- Elixir 1.16+ / OTP 26+
- PostgreSQL 15+ con extensión pgvector
- Rust (para compilar el NIF tree-sitter): `rustup` + stable toolchain

### 16.2 Hardware (configuración local recomendada)
- RAM: 4 GB disponibles (2.8 GB Phi-4-mini + 1.1 GB BGE-M3 + margen)
- GPU: 6 GB VRAM para GPU offloading (CPU también funciona, más lento)
- Disco: ~10 GB para modelos GGUF + DB de un proyecto mediano

### 16.3 Dependencias Elixir
```
ecto_sql ~> 3.11       PostgreSQL ORM
postgrex ~> 0.18       Driver PostgreSQL
pgvector ~> 0.3        Tipo vector para Ecto
req ~> 0.5             Cliente HTTP
jason ~> 1.4           JSON
toml ~> 0.7            Parser TOML para config
rustler ~> 0.34        NIF Rust bridge
apero path: ../apero   Utilidades del ecosistema
arrea path: ../arrea   Orquestación paralela
alaja path: ../alaja   CLI framework + terminal rendering
file_system ~> 1.0     File watcher nativo
alaja path: ../alaja   CLI framework + terminal rendering (reemplaza progress_bar y table_rex)
```

### 16.4 Build del proyecto
```bash
# Primera vez
mix deps.get
mix ecto.create && mix ecto.migrate
mix escript.build   # genera binario ./delfos

# Para CI sin Rust (NIF desactivado, fallback a GenericParser)
RUSTLER_SKIP_COMPILE=true mix escript.build
```

---

## 17. Ciclo de Vida de un Proyecto en Delfos

```
1. SETUP
   delfos doctor               # verificar prerequisites
   delfos config show          # revisar configuración
   delfos config preset local  # ajustar si es necesario
   # Arrancar modelos si local (ver docs/LLM_USAGE.md):
   llama-run embed &
   llama-run gpt_oss medium &

2. INTEGRACIÓN CON AGENTES
   delfos integrate claude-code   # o delfos integrate all --yes
   # Arrancar MCP si no es automático:
   delfos mcp &

3. INDEXADO INICIAL
   cd /ruta/proyecto
   delfos init .
   # (scan --full se ejecuta automáticamente)

4. GENERACIÓN DE RESÚMENES
   delfos summarize              # genera resúmenes LLM (tarda minutos)

5. USO DIARIO
   delfos watch &                # o delfos scan en post-save hooks
   delfos query "autenticación"
   delfos explain UserController.create
   delfos audit

6. MANTENIMIENTO
   delfos scan --full            # después de cambios grandes
   delfos summarize --force      # actualizar resúmenes tras refactoring
   delfos doctor                 # verificar salud del índice
```

---

## 18. Comportamiento Esperado del Agente

Las instrucciones que `delfos integrate` escribe en CLAUDE.md/AGENTS.md definen
el contrato esperado del agente:

**SIEMPRE usar Delfos primero para:**
- Empezar una tarea → `delfos_context(task)`
- Encontrar dónde está algo → `delfos_search(query)`
- Antes de editar una función → `delfos_symbol(name)` + `delfos_impact(name)`
- Trazar flujo de llamadas → `delfos_callers(name)` / `delfos_callees(name)`

**NUNCA leer archivos directamente cuando Delfos puede responder:**
El campo CODE en `delfos_symbol` incluye el código fuente. No hace falta
abrir el fichero para ver la implementación.

**Cómo interpretar el formato de respuesta:**
- SUMMARY: confiar en él — es LLM sobre el código real
- RISK: si cycle=true, proceder con cuidado al refactorizar
- RELATED: símbolos semánticamente similares, explorar si la query no está clara
- CALLERS/CALLEES count=0: puede significar grafo incompleto (compilar primero)

---

## 19. Notas de Implementación Críticas

### Ecto + floats
Las comparaciones de campos `:float` en Ecto requieren literales float.
`risk_score > 10` falla en compilación. Usar `risk_score > 10.0`.

### mix xref y OTP mismatch
Cuando delfos (OTP 26) escanea un proyecto compilado con OTP diferente,
`mix xref` puede fallar con errores de beam loading. El fallback es el parser
regex de imports de Elixir. Para el grafo completo: `cd proyecto && mix compile`.

### MCP y stdout
El servidor MCP usa stdout como canal de transporte. Cualquier `IO.puts` o
`Logger.info` contaminaría el protocolo. El modo `:mcp` desactiva Logger de
consola y el Watcher (que escribe logs). Los errores críticos van a stderr.

### Tree-sitter NIF scheduler
El NIF usa `DirtyCpu` scheduler para no bloquear el scheduler Erlang durante
el parseo AST. Para archivos muy grandes (>10k líneas) el parseo puede tardar
100-200ms en el scheduler dirty.

### Embeddings y nil
Los embeddings pueden ser nil si el servidor no está disponible durante el scan.
Las queries de búsqueda siempre incluyen `where: not is_nil(embedding)`.
`delfos doctor` reporta el porcentaje de símbolos sin embedding.

### RRF y resultados vacíos
Si un motor devuelve lista vacía, su contribución al RRF es cero pero no
rompe el merge. El resultado final puede venir solo del vector o solo del BM25.

---

## 20. Cambios respecto a la versión 0.5 de referencia

Las secciones 1–19 de este SPEC describen el comportamiento **objetivo**
del sistema. Las versiones v0.2.0 a v0.3.1 publicadas en GitHub han ido
implementando partes de ese objetivo. Esta sección documenta qué está
realmente en cada release.

### v0.2.0 — Initial release

- MCP server JSON-RPC 2.0 sobre stdio, 8 herramientas (`delfos_search`,
  `delfos_symbol`, `delfos_context`, `delfos_callers`, `delfos_callees`,
  `delfos_impact`, `delfos_audit`, `delfos_files`).
- Búsqueda híbrida (vector + BM25 + grafo) con RRF.
- CandilBridge para enrutar chat/embeddings OpenAI-compat a `Candil`.
- `delfos integrate <agent>` para 7 agentes (claude-code, opencode,
  cursor, aider, codex, zed).

### v0.3.0 — Doctor sobre Botica.Doctor, --help por comando

- `delfos doctor` reescrito sobre `Botica.Doctor` (antes llamaba a un
  inexistente `Apero.Doctor`). Añade `--interactive` (pregunta antes
  de aplicar cada fix), `--db-only` / `--llm-only` para subsets de
  checks, y `--json` para consumo programático.
- `delfos models [--probe]` para ver y sondear los modelos activos
  (embedding + LLM) — incluye verificación de `dim` contra la columna
  `symbols.embedding` en PostgreSQL.
- `--help` y `-h` funcionan globalmente y en cada subcomando.
- Mensajes de error contextualizados: hints como "run delfos doctor" o
  "start llama-server --port 9998" en lugar de `inspect(reason)`.

### v0.3.1 — Backup timestamp en integrate

- Nuevo helper `Delfos.CLI.Commands.Integrate.safe_write/2`:
  toda escritura a `~/.claude.json`, `~/.config/opencode/config.json`,
  `.cursor/mcp.json`, `.aider.conf.yml`, `~/.codex/config.toml`,
  `~/.config/zed/settings.json` ahora hace backup timestamp
  (`<path>.bak-<unix_seconds>`) antes de sobrescribir.
- Si el archivo destino no existe o está vacío, no crea backup
  (no hay contenido del usuario que preservar).
- Cursor: migración de `.cursorrules` (deprecado en 0.45+) a
  `.cursor/rules/delfos.mdc` con frontmatter YAML.
- Aider: merge del bloque `read:` existente en lugar de machacarlo
  (YAML no permite dos claves `read:` en el mismo documento).
- Codex: el archivo es **TOML** (`~/.codex/config.toml`), no YAML.
  Top-level key es `[mcp_servers]`, no `[mcpServers]`.

### v0.3.2 — Format fixes (Codex TOML, Cursor MDC, Aider YAML merge)

Re-tag del v0.3.1 con los formatos correctos para los agentes:

- Codex: el archivo es **TOML** (`~/.codex/config.toml`) con key
  `[mcp_servers]`, no YAML. Round-trip verificado con `Toml.decode/1`.
- Cursor: `.cursor/rules/delfos.mdc` con frontmatter YAML, no
  `.cursorrules` (deprecado en 0.45+).
- Aider: merge del bloque `read:` en lugar de duplicar la key.
- `yaml_elixir` añadido como dep temporal (luego eliminado).

### v0.3.3 — Verified formats, regex-based aider merge

- 12 tests reales en `test/delfos/cli/commands/` que cargan Toml y
  Jason de verdad y verifican que los formatos escritos son los que
  cada agente realmente lee.
- `merge_aider_read/1` reemplazado de `YamlElixir` a regex simple —
  YamlElixir requiere Elixir 1.17+ y rompía el soporte 1.15.
- 12 tests pasan en 0.02s sin Alaja ni base de datos.

### Estado actual (v0.3.3)

| SPEC § | Estado en v0.3.3 |
|--------|------------------|
| 9. MCP Server | ✅ Implementado (8 tools, JSON-RPC 2.0, notifications) |
| 10. CLI con Alaja | ✅ Implementado (todos los subcomandos usan Alaja) |
| 11. Configuración Global | ✅ Implementado (TOML + env overrides) |
| 12. Modelos Recomendados | ✅ Documentado + recipes (local / OpenAI / Anthropic) |
| 13. CLI Referencia Completa | ✅ Coincide con `delfos <cmd> --help` |
| 14. Integración con Ecosistema | ✅ 6 agentes con formatos verificados |
| 17. Ciclo de Vida de un Proyecto | ✅ Implementado |
| 4. Pipeline de Indexado | ✅ Implementado |
| 5. Sistema de Parseo | ⚠️ Tree-sitter NIF con fallback regex |
| 6. Módulo LLM | ✅ Implementado (multi-provider + Candil) |
| 7. Sistema de Retrieval | ✅ Implementado (vector + BM25 + graph + RRF) |
| 8. Análisis | ✅ Métricas básicas (churn, cycles, debt) |
| 15. Modelos de Datos Internos | ✅ Coincide con outputs en MCP_TOOLS.md |
| 19. Notas de Implementación | ✅ Documentadas en §20 de este SPEC |

### Verificación

- 12 tests en `test/delfos/cli/commands/integrate_formats_test.exs`
  pasan con parsers reales (Toml.decode_file/1, Jason.decode/1, regex
  para YAML).
- 4 tests en `test/delfos/cli/commands/integrate_test.exs` verifican
  `safe_write/2` (backup, vacío, nested configs).
- Todos los subcomandos exponen `--help` con `@help` string.
- `delfos doctor` carga `Botica.Doctor` y `Botica.Repair.Fixer` y
  produce resultados estructurados.

