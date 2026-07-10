# Plan Integral: Delfos sobre el Ecosistema

## Principio Rector
**Toda funcionalidad existente en pote/alaja/arrea/apero/botica/candil debe ser REUTILIZADA, no reimplementada en Delfos.**

---

## Mapa del Ecosistema

```
                    ┌─────────────────────────────┐
                    │           POTE              │
                    │   Colorimetría + Temas      │
                    └────────────┬────────────────┘
                                 │ depende de
                    ┌────────────▼────────────────┐
                    │          ALAJA              │
                    │  CLI Framework + Terminal   │
                    └────────────┬────────────────┘
                                 │ depende de
         ┌───────────────────────┼──────────────────────────┐
         │                       │                          │
         ▼                       ▼                          ▼
┌─────────────────┐   ┌──────────────────┐   ┌──────────────────────┐
│     ARREA       │   │     APERO        │   │       CANDIL         │
│  Orquestación   │   │  Utilidades      │   │  LLM + Modelos       │
│  paralela       │   │  File, Crypto,   │   │                      │
│  CircuitBreaker │   │  Conf, Git, Env, │   │  (Lo que era LLM     │
└─────────────────┘   │  Docker, OS,     │   │   de apero)          │
                      │  Proc, Cache,    │   └──────────────────────┘
                      │  Retry, Network, │
                      │  SSH, K8s...     │
                      └──────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │       BOTICA        │
                    │  Health Checks +    │
                    │  Feature Flags      │
                    │  (Lo que era doctor │
                    │   de apero)         │
                    └─────────────────────┘
```

**Relaciones:**
- **Pote** → no depende de nadie
- **Alaja** → depende de Pote
- **Arrea** → depende de Alaja
- **Apero** → depende de Arrea, Alaja
- **Candil** → depende de Apero, Arrea (para HTTP/paralelismo)
- **Botica** → no depende de nadie externo
- **Delfos** → depende de todos (Pote via Alaja, Alaja, Arrea, Apero, Candil, Botica)

---

## Diagnóstico Actual (por proyecto)

### 1. POTE — Estado: ❌ Sin usar
**Qué ofrece:**
- Parseo de colores (RGB, HEX, HSL, HSV, CMYK, etc.)
- `Pote.get_color(:primary)`, `Pote.default_colors()`
- `use Pote.Theme` — sistema de temas completo con JSON en disco
- ANSI escapes, contrastes WCAG, gradientes, validación
- Alaja ya tiene `Alaja.Theme` via `use Pote.Theme`

**Qué hace Delfos:**
- ~15 RGB tuples hardcodeados: `{0, 180, 216}`, `{0, 200, 100}`, etc.
- Sin tema, sin `use Pote.Theme`
- `Alaja.Theme` existe pero nunca se referencia

**Plan:**
1. Crear `Delfos.Theme` con `use Pote.Theme` (tema propio con colores Delfos)
2. Reemplazar todos los RGB hardcodeados por `Delfos.Theme.color(:primary)` o cadenas `"theme:primary"`
3. `Alaja.Theme` ya registra su resolver en Pote al boot — Delfos.Theme haría lo mismo

---

### 2. ALAJA — Estado: ⚠️ Uso parcial con anti-patrón grave

**Qué ofrece:**
- `Alaja.CLI.Definition` — DSL declarativo: `command/3`, `flag/3`, `argument/3`, `run/2`
- `Alaja.CLI.Validator` — validación de flags con tipos y valores permitidos
- `Alaja.CLI.ErrorHandler` — "did you mean?" por Jaro distance + exit codes
- `Alaja.CLI.Help` — help auto-generado a partir de las declaraciones
- `Alaja.CLI.GlobalOpts` — 12 flags compartidas (--quiet, --raw, --align, --verbose, --box...)
- `Alaja.Printer` — 12 niveles de severidad (success/error/warning/info/debug/notice...)
- `Alaja.Printer.Interactive` — question/yesno/menu/question_with_options
- `Alaja.Components.Table` — tablas con bordes redondeados, colores por fila/columna
- `Alaja.Components.Box` — cajas con título y 5 estilos de borde
- `Alaja.Components.Bar` / `AnimatedBar` — barras de progreso (8 estilos animados)
- `Alaja.Components.Header` — títulos centrados con subtítulo
- `Alaja.Components.Breadcrumbs`, `Separator`, `Json`, `ColorWheel`, `Gradient`
- `Alaja.Syntax` — syntax highlighting para Elixir, JSON, Markdown
- `Alaja.Wizard` — formularios multi-campo declarativos
- `Alaja.Buffer` — motor de celdas 2D para composición visual

**Problema crítico — Handler Bridge (doble parseo):**

```
Usuario escribe: delfos scan --full --workers 8

1. Alaja DSL parsea correctamente → %{full: true, workers: 8, _args: []}
2. Handler (cli.ex:33) llama build_args/1:
       → ["--full", "--workers", "8"]    ← DECODIFICA el mapa a argv
3. Commands.Scan.run/1 (scan.ex:42) llama OptionParser.parse:
       → vuelve a extraer full: true, workers: 8   ← REPARSEA
```

Esto afecta a **8 de 17 handlers**: scan, query, summarize, doctor, models, integrate, context, explain.
Y a **3 comandos sin handler** que pasan raw args: audit, init, graph.

Además, `build_args/1` (cli.ex:146-153) es frágil: asume que booleano=true es flag, strings no vacías son flag+valor, integers se convierten a string. Cualquier tipo nuevo (float, atom) rompe.

**8 comandos usan `OptionParser.parse` bruto:**
`scan.ex:43`, `query.ex:49`, `summarize.ex:44`, `doctor.ex:36`, `models.ex:37`, `integrate.ex:76`, `context.ex:36`, `explain.ex:43`

**Qué falta además del handler bridge:**
- ❌ No se usa `Alaja.CLI.Validator` en ningún comando
- ❌ No se usa `Alaja.CLI.ErrorHandler` — 14 `System.halt(1)` manuales
- ❌ No se usan `GlobalOpts` (--quiet, --json serían gratis)
- ❌ `status.ex` dibuja bordes de tabla a mano (`┌─│└`) en vez de `Alaja.Components.Table`
- ❌ `doctor.ex` imprime `=== DELFOS DOCTOR ===` en vez de `Box.print`
- ❌ `scan.ex` imprime progreso raw en vez de `AnimatedBar`
- ❌ `setup/db.ex` y `llm.ex` usan `IO.gets` en vez de `Interactive.question`
- ❌ `integrate.ex` usa `IO.gets("")` para confirmación en vez de `Interactive.yesno`

**Plan:**

**Fase A — Eliminar handler bridge (crítico):**
1. Cada `Commands.X.run/1` acepta `map` de opts directamente (en lugar de `list` argv)
2. Eliminar `build_args/1` y todos los handlers intermedios
3. Cada flag se declara en el DSL y se recibe como `opts.full`, `opts.workers`
4. Eliminar `OptionParser.parse` de los 8 comandos
5. Añadir `halt_on_error: true` en el `use Alaja.CLI.Definition`

**Fase E — Componentes visuales:**
1. `doctor.ex`: `=== DELFOS DOCTOR ===` → `Alaja.Components.Box.print("DELFOS DOCTOR", border: :rounded)`
2. `status.ex`: bordes manuales → `Alaja.Components.Table.print/1`
3. `scan.ex`: progreso raw → `Alaja.Components.AnimatedBar`
4. `setup/*.ex`: `IO.gets` → `Alaja.Printer.Interactive.question/1`
5. `integrate.ex`: `IO.gets("")` → `Interactive.yesno("Continue?", default: :yes)`

---

### 3. ARREA — Estado: ✅ Bueno, con gaps menores

**Qué ofrece:**
- `Arrea.run_sync/2` — paralelismo (✅ usado en file_processor, hybrid_search)
- `Arrea.Command.execute/2` — shell seguro con timeout real (✅ usado en init, graph_builder, churn_analyzer)
- `Arrea.Parallel` — fachada para parallel (✅ usado)
- `Arrea.CircuitBreaker` — protección de calls externos
- `Arrea.Policies` — retry/stop/continue configurable
- `Arrea.Telemetry` — eventos de sistema
- `Arrea.stats/0` — monitoreo de workers

**Qué falta:**
1. ❌ `CircuitBreaker` para HTTP calls a LLM/embedding en `llm/client.ex`
2. ❌ `Arrea.Policies` en `run_sync` de `file_processor.ex` y `hybrid_search.ex`

**Plan (Fase F):**
1. Envolver cada provider (local/openai/anthropic) con `Arrea.CircuitBreaker`
2. Usar `Arrea.Policies.tolerant(max_retries: 2)` en file_processor

---

### 4. APERO — Estado: ⚠️ Infrautilizado + 🗑️ Llm.* a migrar

**⚠️ CORRECCIÓN DE DOMINIO:** Los módulos `Apero.Llm.*` (creados en Fase 1.2) **NO pertenecen aquí**. Candil es el proyecto de LLM. Hay que moverlos.

**Qué ofrece Apero (dominio correcto):**

| Módulo | Ofrece | Delfos usa? |
|---|---|---|
| `Apero.File` | read/write/copy/move/delete/exists?/dir?/checksum/tmp | ❌ Raw File module (~30+ llamadas) |
| `Apero.File.IO` | atomic_write/2, atomic_rename/2 | ❌ |
| `Apero.File.Path` | cwd/0, join/1, ensure_dir/1 | ❌ |
| `Apero.Git` | ensure_clone/2, add/2, commit/2, push/3 | ❌ Raw System.cmd("git") |
| `Apero.Git.Local` | branch_name/0, last_commit/0, remote/0, has_changes?/0 | ❌ |
| `Apero.Crypto.Cipher` | encrypt/decrypt AES-256-GCM | ✅ Usado en Config.Manager |
| `Apero.Crypto.Random` | generate_key/0, random_bytes/1 | ✅ Usado |
| `Apero.Crypto.Hash` | sha256/1, md5/1, checksum/2 | ❌ :crypto.hash directo |
| `Apero.Conf` | load/1 (auto-detecta JSON/YAML/TOML), format | ❌ Jason.decode + Toml.decode manual |
| `Apero.Env` | load/1 (desde .env), fetch!/1 | ❌ System.get_env raw |
| `Apero.Cache` | put/get/fetch con ETS/Redis/Memcached | ❌ ETS directo (si usa) |
| `Apero.Retry` | with/2 (exponential backoff + jitter), schedule_next/7 | ❌ Process.sleep polling |
| `Apero.Proc` | which/1, command_exists?/1, ps/0 | ❌ System.find_executable raw |
| `Apero.OS` | info/0, in_container?/0, arch/0 | ❌ No usado |
| `Apero.Docker` | up/down/restart/exec | ❌ No usado (infra) |
| `Apero.Compress` | zip/tar/gzip | ❌ No usado |
| `Apero.Network` | ping/1, port_open?/2 | ❌ No usado |
| `Apero.SSH` | connect/2, exec/3 | ❌ No usado |

**Plan (Fase C):**
1. Config.Manager file ops → `Apero.File`, `Apero.Conf`, `Apero.File.IO`
2. Polling en RepoStarter y setup/llm → `Apero.Retry.with/2`
3. Git commands en init.ex → `Apero.Git.Local`
4. Env vars → `Apero.Env.fetch!/1`
5. :crypto.hash → `Apero.Crypto.Hash`
6. System.find_executable → `Apero.Proc.which`

**Migración Apero.Llm.* → Candil:**
Los 3 módulos creados en Fase 1.2 se mueven a Candil:

| Actual (Apero) | Destino (Candil) |
|---|---|
| `Apero.Llm.Health` | `Candil.Health` (ping de providers) |
| `Apero.Llm.ConfigManager` | `Candil.ConfigManager` (validación/normalización) |
| `Apero.Llm.Embeddings` | `Candil.Embeddings` (batching unificado) |

Y en Delfos:
- `probe.ex:35` cambia `Apero.Llm.Health.ping/3` → `Candil.Health.ping/3`

---

### 5. BOTICA — Estado: ❌ Sin usar (dependencia cargada pero ignorada)

**Qué ofrece vs qué hace Delfos:**

| Botica | Delfos actual | Problema |
|---|---|---|
| `Botica.Doctor.run/1` — checks en paralelo con timeout | `Diagnostics.run()` — 6 checks secuenciales | ❌ Reimplementación manual |
| `Botica.Doctor.fix/1` — auto-repair con reporte | `--fix` en doctor.ex: **no hace nada** (código muerto) | ❌ `_fix_mode` ignorado |
| `Botica.Doctor.summary/1` — `%{ok:, warning:, error:, passed?:}` | `Enum.reduce` manual en doctor.ex | ❌ Reimplementado |
| `Botica.Doctor.health_check/1` — single :ok/:degraded/:fail | `Delfos.Health` con `SELECT 1` raw | ❌ Reimplementado |
| `Botica.Doctor.validate/1` — valida config de checks | No existe en Delfos | ❌ Gap |
| `Botica.Doctor.batteries/0` — PostgreSQL, Redis, Memory, Disk | PostgreSQL check manual con SQL | ❌ Reimplementado |
| `Botica.Batteries.PostgreSQL` — `pg_isready` + versión | `SELECT 1` raw | ❌ Reimplementado |
| `Botica.Flags` — feature flags con ETS | No existe en Delfos | ❌ Gap |
| `Botica.Flags.Store` — GenServer para writes (¡ya corre!) | Nada — ETS table ocupando memoria | ❌ Desperdicio |
| `Botica.Check.Behaviour` — macro para checks reusables | Checks = funciones privadas en Diagnostics | ❌ Sin estructura |
| `Botica.Repair.Fixer` — ejecuta fixes con reporte | No existe en Delfos | ❌ Gap |

**Datos clave:**
- Botica se compila, arranca OTP app `:permanent`, crea ETS `:botica_flags`, inicia `Botica.Flags.Store` GenServer
- **Cero llamadas** a Botica desde ningún .ex en lib/ o test/
- Antes se usaba (v0.3.0, commit `ce746f2`), se eliminó en el refactor de Fase 2 (commit `7513fa9`)

**Plan (Fase B):**

**B.1 — Migrar Diagnostics a Botica.Doctor:**
```elixir
# diagnostics.ex pasa a ser solo la definición de checks:
def checks do
  Botica.Doctor.batteries() ++ [
    %{id: :config_file, name: "Config file", ...},
    %{id: :encryption_key, name: "Encryption key", ...},
    %{id: :migrations, name: "DB migrations", ...},
    %{id: :embed_provider, name: "Embedding provider", ...},
    %{id: :llm_provider, name: "LLM provider", ...}
  ]
end

def run do
  config = %{app_name: "delfos", checks: checks()}
  {:ok, results} = Botica.Doctor.run(config)
  results
end
```

**B.2 — Arreglar `--fix`:**
```elixir
# doctor.ex
defp run_pretty(fix_mode, interactive) do
  config = %{app_name: "delfos", checks: Diagnostics.checks()}
  {:ok, results} = Botica.Doctor.run(config)
  
  if fix_mode do
    {:ok, report} = Botica.Doctor.fix(config)
    mostrar_reporte(report)
  end
  
  mostrar_resultados(results)
end
```

**B.3 — `Delfos.Health` via Botica:**
```elixir
defp run_checks do
  config = %{app_name: "delfos", checks: [
    Botica.Batteries.PostgreSQL.check_def()
  ]}
  result = Botica.Doctor.health_check(config)
  Logger.info("Health: #{result.status}")
end
```

**B.4 — Feature flags con Botica.Flags:**
- Flags para: modo MCP, modo debug, watch activo
- `Botica.Flags.define(:mcp_mode, default: false)` en boot
- Consultar con `Botica.Flags.enabled?(:mcp_mode)`

---

### 6. CANDIL — Estado: ⚠️ Bridge superficial + destino de Apero.Llm.*

**Dominio correcto de Candil:**
- LLM inference (chat, embed, stream)
- Model management (download, start, stop engines)
- Provider abstraction (OpenAI, Anthropic, Ollama, OpenAI-compat)
- **Health de providers** (← desde Apero.Llm)
- **ConfigManager de LLM** (← desde Apero.Llm)
- **Embeddings batching** (← desde Apero.Llm)

**Modelo actual de Delfos:**
```
Delfos.LLM.Client
  ├── CandilBridge (chat/embed via Candil)
  │     └── Construye %Candil.Provider{} y %Candil.Model{} nuevos cada vez
  └── HTTP directo (fallback si no Candil o Anthropic)
```

**Problemas:**
1. ❌ `Candil.Config` no se usa — structs Provider/Model se reconstruyen en cada llamada
2. ❌ No usa `Candil.Engine.start/2`/`stop/1` para gestión de modelos locales
3. ❌ No usa `Candil.Conversation` para gestión de contexto
4. ❌ No usa `Candil.stream/4` para streaming (ni siquiera Delfos hace streaming)
5. ❌ HTTP client duplicado en `client.ex:140-200` que Candil ya tiene
6. ❌ `Candil.Registry` no arranca en producción (solo en test)
7. ❌ `Code.ensure_loaded?(Candil)` siempre true (es dep compilado) — fallback es dead code
8. ❌ Sin tests para CandilBridge

**Plan (Fase D):**

**D.1 — Migrar Apero.Llm.* a Candil:**
- `Apero.Llm.Health` → `Candil.Health` (ping de endpoints)
- `Apero.Llm.ConfigManager` → `Candil.Config` (ya existe — fusionar)
- `Apero.Llm.Embeddings` → `Candil.Embeddings`
- Actualizar `probe.ex` y referencias en Delfos

**D.2 — Usar Candil.Config registry:**
```elixir
# En boot de Delfos.Application:
Candil.Config.register_provider(%Candil.Provider{
  alias: :delfos_local,
  type: :openai_compatible,
  base_url: cfg[:embed_url]
})
# Luego el bridge solo pasa el alias:
Candil.chat(:delfos_local, messages)
```

**D.3 — Eliminar HTTP duplicado:**
- Sacar `embed_local/2`, `chat_openai/3`, etc. de `client.ex`
- Todo OpenAI-compat via Candil (que ya maneja Req, auth, errores)
- Anthropic queda como directo (Candil no lo soporta)

**D.4 — Arrancar Candil.Registry en producción:**
- `Candil.Application` debería arrancar `{Registry, keys: :unique, name: Candil.Registry}`
- O Delfos lo arranca en su supervision tree

---

## Resumen de Carga por Fase

| Fase | Proyectos | Días est. | Descripción |
|------|-----------|-----------|-------------|
| **A** | delfos | 2 | Eliminar handler bridge: CLI opts directos, no OptionParser |
| **B** | delfos + botica | 2 | Adoptar Botica.Doctor para doctor, --fix funcional, Health |
| **C** | delfos | 2 | Adoptar Apero: File, Conf, Retry, Git, Hash, Proc |
| **D** | delfos + candil + apero | 2 | Mover Apero.Llm.* → Candil; usar Candil.Config; unificar HTTP |
| **E** | delfos | 2 | Componentes Alaja: Table, Box, Bar, Interactive en lugar de raw |
| **F** | delfos | 1 | CircuitBreaker + Policies via Arrea |
| **G** | delfos + pote | 1 | Pote.Theme: colores temáticos |
| **H** | delfos | 3 | Tests para todo lo migrado |
| **Total** | | **~15 días** | |

## Orden de Ejecución

```
Fase A (CLI handler bridge) ───┬── Fase B (Botica) ──┐
                               │                     │
                               └── Fase E (Alaja visual) ─┤
                                                          │
Fase C (Apero utilidades) ───────────────────────────────┤
                                                          │
Fase D (Candil + mover Apero.Llm) ───────────────────────┤
                                                          │
Fase F (Arrea circuit breaker) ──────────────────────────┤
                                                          │
Fase G (Pote theme) ─────────────────────────────────────┤
                                                          ▼
                                                    Fase H (Tests)
```

Se pueden paralelizar: C + D + F + G tras A.
B y E dependen de A.

---

## Bloqueantes
1. **Handler bridge** (Fase A) — el anti-patrón más grave. Sin esto el CLI no aprovecha Alaja en absoluto.
2. **Botica --fix** (Fase B) — actualmente es código muerto. El usuario cree que auto-repara pero no hace nada.
3. **Apero.Llm.* mal ubicados** (Fase D) — se crearon en el proyecto equivocado. Mover a Candil.

---

## Lo que NO necesita Delfos implementar
- ✅ CLI parsing + validación → Alaja.CLI.Definition + Validator
- ✅ Output visual (tablas, cajas, barras) → Alaja.Components.*
- ✅ Input interactivo → Alaja.Printer.Interactive
- ✅ Paralelismo y timeouts → Arrea.run_sync
- ✅ Circuit breaker → Arrea.CircuitBreaker
- ✅ Health checks y diagnóstico → Botica.Doctor
- ✅ Feature flags → Botica.Flags
- ✅ Colores y temas → Pote.Theme (via Alaja.Theme)
- ✅ File I/O seguro → Apero.File
- ✅ Config parsing (JSON/YAML/TOML) → Apero.Conf
- ✅ Env vars → Apero.Env
- ✅ Git operations → Apero.Git
- ✅ Retry con backoff → Apero.Retry
- ✅ Hash/checksum → Apero.Crypto.Hash
- ✅ LLM chat/embed → Candil
- ✅ Health LLM providers → Candil.Health (ex Apero.Llm.Health)
- ✅ Model management → Candil.Engine
- ✅ Streaming LLM → Candil.Stream
