# Plan Integral: Delfos sobre el Ecosistema

## Principio Rector
**Toda funcionalidad existente en pote/alaja/arrea/apero/botica/candil debe ser REUTILIZADA, no reimplementada en Delfos.**

---

## Diagnóstico Actual (por proyecto)

### 1. POTE — Estado: ❌ Sin usar
**Qué ofrece:**
- Parseo de colores (RGB, HEX, HSL, HSV, etc.)
- `Pote.get_color(:primary)`, `Pote.default_colors()`
- `use Pote.Theme` — tema completo con JSON en disco
- ANSI escapes, contrastes WCAG, gradientes

**Qué hace Delfos:**
- ~15 RGB tuples hardcodeados: `{0, 180, 216}`, `{0, 200, 100}`, etc.
- Sin tema, sin `use Pote.Theme`

**Plan:**
1. Crear `Delfos.Theme` con `use Pote.Theme` (tema propio)
2. Reemplazar todos los RGB hardcodeados por `Delfos.Theme.color(:primary)` o referencias temáticas
3. Alaja ya tiene `Alaja.Theme` via Pote — usarlo como base

---

### 2. ALAJA — Estado: ⚠️ Uso parcial con anti-patrón grave

**Qué ofrece:**
- DSL declarativo: `command/3`, `flag/3`, `argument/3`, `run/2`
- `Alaja.CLI.Validator` — validación de flags/args con tipos y valores permitidos
- `Alaja.CLI.ErrorHandler` — "did you mean?" por Jaro distance
- `Alaja.CLI.Help` — help auto-generado
- `Alaja.Printer.Interactive` — question/yesno/menu
- `Alaja.Components.Table`, `Box`, `Bar`, `AnimatedBar`, `Header`, `Breadcrumbs`
- `Alaja.Printer.print_success/error/warning/info` (12 niveles)
- `GlobalOpts` — `--quiet`, `--raw`, `--align`, `--verbose`, `--box`...

**Problema crítico — Handler Bridge (doble parseo):**

```
Usuario escribe: delfos scan --full --workers 8

1. Alaja DSL parsea correctamente → %{full: true, workers: 8, ...}
2. Handler llama a build_args/1 → ["--full", "--workers", "8"]  ← DECODIFICA
3. Commands.Scan.run/1 llama OptionParser.parse de nuevo  ← REPARSEA
```

Esto anula todas las ventajas del DSL: tipos, valores permitidos, errores de parseo.

**8 comandos usan `OptionParser.parse` bruto:**
`scan.ex:43`, `query.ex:49`, `summarize.ex:44`, `doctor.ex:36`, `models.ex:37`, `integrate.ex:76`, `context.ex:36`, `explain.ex:43`

**Plan:**

**Fase A — Eliminar handler bridge (crítico):**
1. Cada `Commands.X.run/1` debe aceptar `map` de opts directamente (no `list` de argv)
2. Eliminar `build_args/1` y todos los handlers intermedios
3. Cada flag se declara en el DSL y se recibe como `opts.full`, `opts.workers`
4. Eliminar `OptionParser.parse` de los 8 comandos

**Fase B — Componentes visuales:**
1. `doctor.ex`: `=== DELFOS DOCTOR ===` → `Alaja.Components.Box.print("DELFOS DOCTOR", border: :rounded, title: "Diagnostics")`
2. `status.ex`: box-drawing manual (`┌─│└`) → `Alaja.Components.Table.print/1`
3. `scan.ex`: progreso raw → `Alaja.Components.AnimatedBar` o `Bar`
4. `setup/db.ex` y `setup/llm.ex`: `IO.gets` → `Alaja.Printer.Interactive.question/1`

**Fase C — Validación:**
1. Usar `Alaja.CLI.Validator.validate_flags/2` en lugar de nil coalescing manual
2. `System.halt(1)` en 14 lugares → error handler de Alaja o dejar que DSL devuelva `{:error, _}`

**Fase D — GlobalOpts:**
1. Añadir `--quiet` a todos los comandos (ya lo ofrece Alaja gratis)
2. Añadir `--json` como flag de Alaja en lugar de manual

---

### 3. ARREA — Estado: ✅ Bueno, con gaps

**Qué ofrece:**
- `Arrea.run_sync/2` — paralelismo (✅ usado)
- `Arrea.Command.execute/2` — shell seguro (✅ usado)
- `Arrea.CircuitBreaker` — protección de calls externos
- `Arrea.Policies` — retry/stop/continue configurable
- `Arrea.Telemetry` — eventos de sistema
- `Arrea.stats/0` — monitoreo

**Qué falta:**
1. ❌ **CircuitBreaker** para calls HTTP a LLM/embedding (`llm/client.ex`)
2. ❌ **Arrea.Policies** en las llamadas a `run_sync` — para manejar errores de workers

**Plan:**
1. Envolver `Delfos.LLM.Client` con `Arrea.CircuitBreaker` por provider
2. Usar `Arrea.Policies.default()` o `Arrea.Policies.tolerant()` en `file_processor.ex` y `hybrid_search.ex`

---

### 4. APERO — Estado: ⚠️ Infrautilizado

**Qué ofrece (y qué usa Delfos):**

| Módulo Apero | Ofrece | Delfos usa? |
|---|---|---|
| `Apero.File` | read/write/exists?/dir?/checksum/tmp | ❌ Raw File module |
| `Apero.File.IO` | atomic_write/2 (safe writes) | ❌ |
| `Apero.Git.Local` | branch_name/0, last_commit/0, remote/0 | ❌ Shell commands raw |
| `Apero.Crypto.Cipher` | encrypt/decrypt AES-256-GCM | ✅ Usado |
| `Apero.Crypto.Random` | generate_key/0 | ✅ Usado |
| `Apero.Crypto.Hash` | sha256/1, md5/1 | ❌ :crypto directo |
| `Apero.Conf` | load/1 (auto-detect JSON/YAML/TOML) | ❌ Jason.decode + Toml.decode manual |
| `Apero.Env` | load/1, fetch!/1 | ❌ System.get_env raw |
| `Apero.Cache` | put/get/fetch con ETS/Redis | ❌ ETS directo (si usa) |
| `Apero.Retry` | with/2 (exponential backoff + jitter) | ❌ Process.sleep polling |
| `Apero.Proc` | which/1, command_exists?/1 | ❌ System.find_executable raw |
| `Apero.OS` | info/0, in_container?/0 | ❌ No usado |
| `Apero.Llm.Health` | ping/3 | ✅ Usado en probe.ex |
| `Apero.Llm.ConfigManager` | validación/normalización | ✅ (nuevo en este ciclo) |
| `Apero.Llm.Embeddings` | batching | ✅ (nuevo en este ciclo) |

**Plan:**

**Alta prioridad:**
1. `RepoStarter` polling → `Apero.Retry.with/2` (exponential backoff)
2. `setup/llm.ex` polling → `Apero.Retry.with/2`
3. `Config.Manager` File.read+Jason.decode → `Apero.Conf.load/1`
4. `Config.Manager` File.write → `Apero.File.IO.atomic_write/2`
5. `init.ex` File.dir?/exists? → `Apero.File.dir?/exists?`

**Media prioridad:**
6. `init.ex` git commands → `Apero.Git.Local.*`
7. `scanner.ex` File.regular? → `Apero.File.file?`
8. `file_processor.ex` :crypto.hash → `Apero.Crypto.Hash.sha256`
9. `integrate.ex` System.find_executable → `Apero.Proc.which`
10. `churn_analyzer.ex` git log → `Apero.Git.Local.*` si existe

**Baja prioridad:**
11. `setup/llm.ex` cd rm System.cmd → `Apero.VFS.*`
12. `context.ex` File.write → `Apero.File.write`

---

### 5. BOTICA — Estado: ❌ Sin usar (dependencia muerta)

**Qué ofrece vs qué hace Delfos:**

| Botica | Delfos actual | Problema |
|---|---|---|
| `Botica.Doctor.run/1` | `Diagnostics.run()` — 6 checks secuenciales | ❌ Reimplementación manual |
| `Botica.Doctor.fix/1` | `--fix` en doctor.ex: **no hace nada** | ❌ Código muerto |
| `Botica.Doctor.summary/1` | `Enum.reduce` manual en doctor.ex | ❌ Reimplementado |
| `Botica.Doctor.health_check/1` | `Delfos.Health` con SQL raw | ❌ Reimplementado |
| `Botica.Doctor.validate/1` | No existe en Delfos | ❌ Gap |
| `Botica.Doctor.batteries/0` | PostgreSQL check manual | ❌ Reimplementado |
| `Botica.Batteries.PostgreSQL` | SQL `SELECT 1` raw | ❌ Reimplementado |
| `Botica.Flags` | No existe en Delfos | ❌ Gap |
| `Botica.Check.Behaviour` | Checks = funciones privadas | ❌ Sin estructura |

**Plan:**

**Fase 1 — Adoptar Botica.Doctor para `delfos doctor`:**
1. Migrar `Delfos.Config.Diagnostics` a usar `Botica.Doctor.run/1`:
   - Definir checks como lista de `%{id:, name:, description:, priority:, check:, fix:, fix_command:}`
   - Usar `Botica.Doctor.batteries()` para PostgreSQL
   - Checks custom: config file, encryption key, migrations, embed/LLM providers
2. `delfos doctor --fix` → `Botica.Doctor.fix/1` (¡por fin funcional!)
3. `delfos doctor --json` → Jason.encode del resultado de Botica
4. Output con Alaja components (Box, Table) en lugar de raw print

**Fase 2 — Adoptar Botica.Doctor para `Delfos.Health`:**
1. `Delfos.Health` (periodic GenServer) → `Botica.Doctor.health_check/1`
2. Checks periódicos: PostgreSQL, pgvector

**Fase 3 — Botica.Flags para feature flags:**
1. Feature flags para: modo MCP, modo debug, etc.
2. Rollout gradual de nuevas features

---

### 6. CANDIL — Estado: ⚠️ Bridge superficial

**Modelo actual:**
```
Delfos.LLM.Client
  ├── CandilBridge (chat/embed via Candil)
  │     └── Construye %Candil.Provider{} y %Candil.Model{} nuevos cada vez
  └── HTTP directo (fallback si no Candil o Anthropic)
```

**Problemas:**
1. ❌ `Candil.Config` no se usa — structs se reconstruyen en cada llamada
2. ❌ No usa `Candil.Engine.start/2`/`stop/1` para gestión de modelos locales
3. ❌ No usa `Candil.Conversation` para gestión de contexto
4. ❌ No usa `Candil.stream/4` para streaming
5. ❌ HTTP client duplicado en `client.ex` (lines 140-200) que Candil ya tiene
6. ❌ `Candil.Registry` no arranca en producción (solo en test)

**Plan:**

**Fase 1 — Usar Candil.Config:**
1. Registrar providers y models en `Candil.Config` al boot de Delfos
2. Bridge solo pasa alias (ej: `:delfos_openai`) en lugar de reconstruir structs

**Fase 2 — Unificar HTTP client:**
1. Eliminar HTTP duplicado en `client.ex` — todo via Candil para OpenAI-compat
2. Anthropic queda como directo (Candil no lo soporta aún)

**Fase 3 — Gestión local de modelos (opcional):**
1. `Candil.download_model/1`, `Candil.start_engine/2` en `setup/llm.ex`
2. Reemplazar `llm-server.sh` con gestión via Candil

---

## Resumen de Carga por Fase

| Fase | Proyectos | Días est. | Dependencias |
|------|-----------|-----------|--------------|
| **A** Eliminar handler bridge (CLI) | delfos | 2 | — |
| **B** Adoptar Botica para doctor | delfos + botica | 2 | Fase A |
| **C** Adoptar Apero (File, Conf, Retry, Git) | delfos + apero | 3 | — |
| **D** Adoptar Candil.Config + unificar HTTP | delfos + candil | 2 | — |
| **E** Componentes Alaja (Table, Box, Bar, Wizard) | delfos | 2 | Fase A |
| **F** CircuitBreaker + Policies (Arrea) | delfos | 1 | — |
| **G** Pote.Theme + colores temáticos | delfos + pote | 1 | — |
| **H** Tests para todo lo migrado | delfos | 3 | Fases A-G |

**Total estimado: ~16 días**

---

## Dependencias entre Fases

```
A (CLI handler bridge) ─┬── B (Botica doctor) ──┐
                         │                       │
                         └── E (Alaja visual) ──┤
                                                │
C (Apero utilidades) ──────────────────────────┤
                                                │
D (Candil.Config) ─────────────────────────────┤
                                                │
F (Arrea circuit breaker) ─────────────────────┤
                                                │
G (Pote theme) ────────────────────────────────┤
                                                ▼
                                          H (Tests)
```

Se pueden paralelizar: C + D + F + G pueden ir en paralelo después de A.
B y E dependen de A.

---

## Bloqueantes
1. **Handler bridge** (Fase A) — el anti-patrón más grave. Sin esto, el CLI no aprovecha Alaja correctamente.
2. **Botica --fix** (Fase B) — actualmente es código muerto. El usuario cree que auto-repara pero no hace nada.
3. **Botica dependencia muerta** — corre OTP app + ETS table sin beneficio hasta que se adopte.

---

## Lo que NO necesita Delfos implementar
- ✅ CLI parsing y validación → Alaja.CLI.Definition + Validator
- ✅ Output visual (tablas, cajas, barras) → Alaja.Components.*
- ✅ Input interactivo → Alaja.Printer.Interactive
- ✅ Paralelismo y timeouts → Arrea.run_sync
- ✅ Circuit breaker → Arrea.CircuitBreaker
- ✅ Health checks y diagnóstico → Botica.Doctor
- ✅ Feature flags → Botica.Flags
- ✅ Colores y temas → Pote.Theme
- ✅ File I/O seguro → Apero.File
- ✅ Config parsing (JSON/YAML/TOML) → Apero.Conf
- ✅ Env vars → Apero.Env
- ✅ Git operations → Apero.Git
- ✅ Retry con backoff → Apero.Retry
- ✅ Hash/checksum → Apero.Crypto.Hash
- ✅ LLM chat/embed → Candil
- ✅ Model management → Candil.Engine
- ✅ Streaming LLM → Candil.Stream
