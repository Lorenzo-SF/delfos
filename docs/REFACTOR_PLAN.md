# Delfos — Plan de Refactor Integral (post-auditoría)

> **Estado**: 🟢 EN EJECUCIÓN — v2.4.0 publicado 2026-07-16 + 7 commits adicionales.
> **Generado**: 2026-07-15. **Última actualización**: 2026-07-16 (post-sesión v2.4.0).
> **Auditoría base**: 3 sesiones de lectura (commands + deps + docs + git history).
> **Decisiones**: confirmadas por el usuario (Lorenzo-SF) — respuesta 1-7.
> **Ejecutado en**: rama `refactor-and-sync`, pusheado a `origin/refactor-and-sync`.
> **Modelos usados**: implementación directa con M3 + gpt-oss-20b local para diffs; análisis/review con `MiniMax-M3`.
> **Tag actual**: `v2.4.0` (mix.exs:4, source_ref actualizado).
> **Branch listo para merge a `main`**: ✅ sí, 23 commits ahead.

## 0.2 Estado de implementación (post-v2.4.0 + patches)

> Snapshot fechado el **2026-07-16**. La próxima sesión debe arrancar
> leyendo §0.2 + §15 (aliases) + §7 (task list con ✅/❌) antes de
> tocar código.

### FASE A — Quick Wins · ✅ **100%**

| # | Tarea | Commit | Estado |
|---|-------|--------|--------|
| A1 ✅ | Eliminar aliases deprecados | `e01455e` | ✅ |
| A2 ✅ | Eliminar `delfos context` | `e01455e` | ✅ |
| A3 ✅ | Eliminar `config wizard/doctor/probe` | `e01455e` | ✅ |
| A4 ✅ | `[mcp]` section en `config show` | `e01455e` | ✅ |
| A5 ✅ | `summarize`: Task.async_stream → Arrea.run_sync | `e01455e` | ✅ |
| A6 ✅ | 5 `System.find_executable` → `Apero.Proc.which/1` | `e01455e` | ✅ |
| A7 ✅ | doctor `--interactive` → `--guided` | `e01455e` | ✅ |

### FASE B — Refactor estructural · ✅ **100%**

| # | Tarea | Commit | Estado |
|---|-------|--------|--------|
| B1 ✅ | Eliminar argv-round-trip en 14 handlers | `420c150` | ✅ |
| B2 ✅ | Eliminar 6 `Alaja.CLI.OptionsParser.parse` | `420c150` | ✅ |
| B3 ✅ | Quitar `--symbol` de agents, absorber en explain | `463b024` | ✅ |
| B4 ✅ | `delfos status --stats` absorbe `stadistics` | `e01455e`+`cc6ffa9` | ✅ |
| B5 ✅ | `delfos config` 8 sub-comandos limpios | `cc6ffa9` | ✅ |
| B6 ✅ | `help_text/0` uniforme en todos los commands | `cc6ffa9` | ✅ |
| B7 ✅ | `--llm-less` flag (query/explain/audit) | `ef708fa` | ✅ |
| B8 ✅ | `--with-explanation` flag (audit/agents) | `ef708fa` | ✅ |

### FASE C — Ecosystem migration · ✅ **83% (5 de 6 + CVE)**

| # | Tarea | Commit | Estado |
|---|-------|--------|--------|
| C1 ✅ | `Apero.Retry.with` → `Arrea.CircuitBreaker` (defense-in-depth) | `4580849` | ✅ |
| C2 ✅ | `setup/db.ex`: docker calls → `Trebejo.Docker` | `aad6e32` | ✅ |
| C3 ✅ | `bash -c "$cmd"` → `Trebejo.SafeCommand.run_legacy` | `0688f0c` | ✅ |
| C4 ✅ | `setup/llm/llama_cpp.ex` 10 prompts → script/manual (0-3 prompts) | `3807334` | ✅ |
| C5 ✅ | `setup/llm/external.ex` sin embedding prompts | `8ed917f` | ✅ |
| C6 ✅ | `ensure_embedding_server/0` auto-arranque | `655b8b9` | ✅ |
| C7-C10 | Componentes Alaja (MultiBar, Pulsar, AnimatedBar, Wizard) | — | ❌ **pendiente** (cosmetic, baja prioridad) |
| CVE ✅ | `req ~> 0.6.3` override (clear CVE-2026-49755 + CVE-2026-49756) | `e02695b` | ✅ |

### FASE D — Integraciones + docs · ✅ **83%**

| # | Tarea | Commit | Estado |
|---|-------|--------|--------|
| D1 ✅ | `delfos integrate vscode` | `9beaa99` | ✅ |
| D2 ✅ | Tests para 5 nuevos formatos | `d1de52c` | ✅ |
| D3 ✅ | Añadir claude-desktop, windsurf, continue, roo-code | `9beaa99` | ✅ |
| D4 ✅ | Sync `LLM_USAGE.md` + `MCP_TOOLS.md` | `3a3c3ca` | ✅ |
| D5 ✅ | Sync `README.md` + `audit_delfos.txt` | `3a3c3ca` | ✅ |
| D6 ✅ | CHANGELOG.md + version bump 2.4.0 | (este commit) | ✅ |

### Pendientes fuera del plan

| # | Item | Estado |
|---|------|--------|
| — | **SPEC.md** reescritura completa (sigue en v0.5) | ❌ solo falta §10/§13 actualizada |
| — | **Bug #25** (callers/callees metaprogrammed) | ❌ sin solución NIF-side |
| — | **`delfos init --with-summary --with-briefing --force`** (Fase E) | ❌ nice-to-have, no implementado |
| — | **`docs/LLM_USAGE.md` desactualizado** — header dice "v2.3.0"; menciona `thinker_*`, no menciona `gguf_dir` ni auto-arranque | ❌ sync pendiente |
| — | **Stale `llm-server.sh` references** — `docs/SPEC.md:942-946` y `docs/debugging.md:194` mencionan un script que NO existe desde v2.3.0 | ❌ doc fixes pendientes |
| — | **`source_ref` en `mix.exs` hardcoded** — debería ser `"v#{@version}"` para auto-sync con el bump | ❌ nice-to-have |
| — | **`delfos config migrate-local` command** — explícito para forzar migración de config stale (ahora es auto-silencioso) | ❌ nice-to-have |

### Resumen ejecutivo

- **Implementado**: 22 de 24 tareas planificadas + 5 fuera-plan (CVE req, D5+D6, thinker removal, Access.get/3 fix, race condition fix).
- **Pendiente**: 1 tarea de Fase C (C7-C10 componentes Alaja, cosmetic, baja prioridad) + 3 fuera-plan (SPEC.md, Bug #25, init --with-X).
- **Código neto**: **-1.842 LOC + ~-50 LOC en C1-C6** + 6 LOC en dead-code cleanup (thinker removal).
- **Tests añadidos**: 13 (Fase D2) + ~10 nuevos en C1/C5/C6/Breakers.
- **Binario actualizado**: `~/bin/delfos` ahora muestra 14 top-level commands, 11 agents en `integrate`, `--stats` en `status`, `--llm-less` en `query/explain/audit`, `--with-explanation` en `audit/agents`. v2.4.0 añade auto-arranque del embed server, defense-in-depth retry+breaker, y setup wizard de 0-3 prompts (script mode).

### Patches post-v2.4.0 (commits adicionales después del tag)

Estos 7 commits se hicieron después de taggear v2.4.0 — son bug fixes y UX improvements detectados durante las pruebas del usuario final:

| Commit | Tipo | Descripción |
|--------|------|-------------|
| `3e0ee33` | test fix | `ManagerTest async: false` — race condition en `process_chunks` (env-var race entre `Application.put_env` paralelos) |
| `52472bc` | chore | `mix format` — normaliza whitespace en archivos C1/C3/C5/C6 |
| `ccbbedb` | refactor | Drop `thinker_*` concept + auto-migrate stale OpenAI config (provider=`openai` + URL=`api.openai.com` → reverte a `:local`) |
| `d69e2f5` | bug fix | `Access.get/3` crash en `CandilBridge.embed_batch/2` — `Application.fetch_env(...)[:dim]` → `compile_env(...)[:dim]` |

### Cómo continúa la próxima sesión

1. Lee §0.2 de este doc (snapshot actual) y §19-20 de `docs/REMAINING_TASKS.md`.
2. Lee `docs/REMAINING_TASKS.md` §21 "Retomar en otra sesión" para el roadmap detallado de v2.5.0.
3. **Recomendación de prioridad** para v2.5.0 (ver §21 de REMAINING_TASKS para detalle):
   - **C7-C10** (componentes Alaja: MultiBar/Pulsar/AnimatedBar/Wizard) — UX muy notable, ~3-4h
   - **Doc sync** (SPEC.md §10/§13, LLM_USAGE.md, docs que mencionan `llm-server.sh` obsolete) — ~2h
   - **R3-R4 cleanup** (dead code en `candil_bridge.ex:132-135`, `@known_models` en llama_cpp) — ~30min
4. Si la sesión se enfoca en C7-C10:
   - `Alaja.Components.MultiBar` ya está implementado en `~/cacafuti/alaja`
   - Usar `lib/delfos/cli/commands/init.ex` como entry point (run/1 tiene la multi-stage flow)
   - `Wizard` va en `lib/delfos/cli/commands/setup.ex` (top-level wizard dispatcher)
5. Si la sesión se enfoca en SPEC.md, arrancar por §10.2 (la lista de comandos) y §13 (CLI reference).

## 0.3 Fase UI/UX — Polish + overhaul completo (v2.5.0+)

> Bloque dedicado. C7-C10 del plan original son **un subset mínimo**
> de lo que se puede hacer con Alaja. La versión 0.5+ de Alaja expone
> 13 componentes (`AnimatedBar`, `MultiBar`, `Pulsar`, `Header`,
> `Box`, `Separator`, `Breadcrumbs`, `ColorWheel`, `Bar`, `Progress`,
> `Table`, `Message`, `Json`). Delfos solo usa 3 (`Header`, `Progress`,
> `Table`). El potencial es enorme.

### Estado actual (post-commit `5c2919c`)

| Componente Alaja | Usado en | Status |
|------------------|----------|--------|
| `Header` | setup wizards, cli banner | ✅ usado |
| `Progress` (simple bar) | `scan.ex` viejo | ⚠️ reemplazado por `AnimatedBar` en `5c2919c` |
| `Table` | `cli.ex` --help | ✅ usado |
| **`AnimatedBar` + ETA** | `scan.ex` (file_processor.ex) | ✅ **integrado** (`5c2919c`) |
| **`Pulsar` splash** | `mcp/server.ex` startup | ✅ **integrado** (`5c2919c`) |
| `MultiBar` (multi-stage) | `init.ex` (scan + summary + briefing paralelos) | ❌ **pendiente (C7)** |
| `Wizard` (unified setup) | `setup.ex` top-level | ❌ **pendiente (C10)** |
| `Box` (boxed output) | `status.ex`, `doctor.ex`, `explain.ex`, `help` | ❌ **no usado** |
| `Separator` (visual dividers) | entre secciones de output | ❌ **no usado** |
| `Breadcrumbs` (command hierarchy) | errores + help | ❌ **no usado** |
| `ColorWheel` (status indicators) | `status.ex` | ❌ **no usado** |
| `Bar` (low-level) | custom visualizations | ❌ **no usado** |
| `Message` (rich messages) | warnings/errors con hints | ❌ **no usado** |

### Roadmap v2.5.0+

**Prioridad ALTA** (UX muy visible):

| # | Item | Impacto |
|---|------|---------|
| **UX1** | **`MultiBar` en `init.ex` `run/1`** — init dispara scan + summary. Hoy corren secuencialmente. MultiBar muestra ambos en paralelo con su propia barra | Alto: usuario ve progreso real de "init" completo |
| **UX2** | **`Box` alrededor de `delfos status`** — actualmente texto plano. Box con título "Delfos Project Status" + secciones coloreadas | Alto: visual jerárquico inmediato |
| **UX3** | **`Box` alrededor de `delfos doctor`** — secciones por check (✓ pass / ✗ fail / ⚠ warn) con colores | Alto: legibilidad |
| **UX4** | **`Wizard` para `setup llm`** — los 4 sub-wizards (script/ollama/external/llama_cpp) comparten estructura pero cada uno tiene su flujo. Wizard unifica | Alto: setup coherente |

**Prioridad MEDIA** (UX nice-to-have):

| # | Item | Impacto |
|---|------|---------|
| **UX5** | `Box` alrededor de output de `delfos explain` (separando "Source code" vs "Explanation" vs "Metadata") | Medio |
| **UX6** | `Separator` entre secciones de `delfos config show` (cada sección `[llm]`, `[embedding]`, etc. con un separator visual) | Medio |
| **UX7** | `Breadcrumbs` en errores: `delfos init > scan > file_processor > elixir_parser > missing dep` | Medio |
| **UX8** | `ColorWheel` en `delfos status` para "Last scan: 2h ago" → rojo si >24h, amarillo si >1h, verde si <1h | Medio |
| **UX9** | `Message` component en warnings/errors con hints accionables (no solo "X failed" sino "X failed. Try: Y") | Medio |

**Prioridad BAJA** (nice-to-have):

| # | Item | Impacto |
|---|------|---------|
| **UX10** | Spinner para operaciones < 5s (single-file embedding, etc.) | Bajo |
| **UX11** | `AnimatedBar` en otros lugares (`delfos summarize`, `delfos integrate`) | Bajo |
| **UX12** | Tema de colores customizable via `~/.config/delfos/theme.json` | Bajo |
| **UX13** | `delfos --version` con splash Pulsar + info del build | Bajo |

### Implementation patterns

Todos los componentes Alaja usan el mismo patrón `render_X(...)` que retorna un `Alaja.Buffer.t/0`, convertible a string via `Alaja.Buffer.to_iodata/1`. Composición:

```elixir
buf =
  Alaja.Components.Header.render("Delfos", subtitle: "v2.5.0")
  |> Alaja.Components.Box.render(title: "Project Status")
  |> Alaja.Components.Table.render(headers: [...], rows: [...])

IO.puts(Alaja.Buffer.to_iodata(buf))
```

Para animación viva (Pulsar, AnimatedBar con `run_infinite`), se usa `spawn` + `Process.send_after` para refrescar cada N ms.

### Métrica objetivo v2.5.0

- ≥ 10 componentes Alaja en uso (de 13 disponibles)
- Tiempo de feedback en `init`/`scan`/`mcp` siempre < 100ms
- Output de todos los comandos usa Box + Separator consistentemente
- Cero output plano sin formato en comandos `show`, `status`, `doctor`

---

## 0.1 Decisiones del usuario (resumen)

1. ✅ Plan aprobado tal cual.
2. ✅ Orden recomendado (Fase A → B → C → D).
3. ✅ Aliases deprecados **ELIMINADOS inmediatamente** — no se mantienen. Quitar sin warning.
4. ✅ Añadir TODAS las integraciones: `vscode`, `windsurf`, `continue`, `claude-desktop`, `roo-code` (10 totales).
5. ✅ Corregir typo `stadistics` → usar `stats`. Decisión: `delfos status --stats` (flag corto en `status`).
6. ✅ Coder model = `llama-local/gpt-oss-20b Q8_K_XL (Unsloth, local)`. Reviewer/tests = `MiniMax-M3`.
7. ✅ `REMAINING_TASKS.md`: marcar implementados 100%, anotar lo que falta. Añadir §16-19 con las 4 fases.

---

## 0. TL;DR

Delfos funciona, compila, y pasa tests. Pero:

1. **Hay comandos duplicados** (`watch`/`serve`/`mcp`, `context`/`agents`, `preset` top-level/`config preset`, etc.) — son deuda técnica.
2. **El wizard de LLM pide 10 cosas para embeddings** cuando solo necesita 0-1.
3. **El CLI no usa el DSL de Alaja al 100%** — 9 comandos re-parsean argv manualmente.
4. **24 `System.cmd` directos** saltándose Trebejo.
5. **Hay un módulo `Delfos.Statistics` ya implementado pero con typo (`stadistics`)** y sin documentar.
6. **Faltan integraciones** (`vscode`).
7. **El CLI no explota los componentes visuales de Alaja** (MultiBar, Wizard, Pulsar, AnimatedBar ya existen).

**Plan**: 24 tareas en 4 fases, ~5-7 sesiones de coder, 1 sesión de documentador, criterio de aceptación por tarea.

**Meta final**: Delfos como producto pulido, sin deuda visible, sin alias muertos, sin comandos redundantes, sin wizards sobre-inteligentes, con cobertura de tests razonable, docs sincronizadas.

---

## 1. Estado actual del proyecto (snapshotted)

| Item | Valor |
|---|---|
| Repo | `/home/merendandum/cacafuti/delfos` |
| Rama activa | `fix-tools-domains` |
| HEAD | `dfd683e` (último commit pushed) |
| Versión `mix.exs` | `2.2.1` |
| Tags | `1.0.0`, `2.0.0`, `2.0.1`, `2.1.0`, `2.2.0`, `2.2.1` |
| Cambios sin commit | 19 archivos modificados + 7 sin trackear |
| Auditoría previa | `audit_delfos.txt` (2026-07-05, branch `m3-delfos-audit`) — parcialmente obsoleta |
| Working tree | 19 modified, 7 untracked (stadistics.ex, statistics.ex, mcp_usage_event.ex, 2 migrations) |
| Tests | 17 archivos en `test/delfos/cli/commands/`, 0 commits changes |
| `mix deps` vulnerable | `req ~> 0.5` (2 CVEs abiertos, pendientes §7.5 NEXT_PHASE) |

### 1.1 Dependencias locales en `mix.exs`

```elixir
{:alaja,    path: "../alaja",    override: true},
{:arrea,    path: "../arrea",    override: true},
{:apero,    path: "../apero",    override: true},
{:candil,   path: "../candil",   override: true},
{:botica,   path: "../botica",   override: true},
{:trebejo,  path: "../trebejo",  override: true},
```

Todas son runtime deps (no `only: [:dev, :test]`). Se usan correctamente en su mayoría — ver §4 para gaps.

### 1.2 Comandos CLI actualmente declarados

```
init           scan            query           audit
summarize      explain         graph           agents
context (*)    config          preset (*)      integrate
doctor         status          watch (*)
mcp            stadistics (*)  serve (*)        version
```
(*) deprecados, alias, o sin track. **Total declarado: 19. Efectivo único: ~13.**

### 1.3 Estado de docs

| Doc | Estado | Acción |
|---|---|---|
| `SPEC.md` | 🔴 Congelado en v0.5; cita comandos y dim obsoletos | Reescribir §1-§13 |
| `HANDOFF.md` | 🟡 Adendum parcial; §4 menciona `Delfos.LLM.Response` (sí existe, falso el reporte anterior) | Limpiar |
| `REMAINING_TASKS.md` | 🟡 §3.1 dice crypto inline, pero `manager.ex` usa `Apero.Crypto.Cipher` | Actualizar |
| `SESSION_STATE.md` | 🟡 Refleja estado v2.2.0; v2.2.1 ya taggeado | Actualizar |
| `NEXT_PHASE.md` | 🟡 Plan §7 cerrado en su mayoría | Marcar histórico |
| `MCP_TOOLS.md` | 🟡 Refiere `serve --mcp` (ahora `mcp`) | Cambiar |
| `LLM_USAGE.md` | 🟡 Tabla desactualizada (dim, comandos) | Reescribir |
| `TEST_PLAN.md` | 🟡 Tareas T1-T22 parcialmente cerradas | Revisar |
| `audit_delfos.txt` | 🟡 Botica "dead code" es FALSO ahora | Corregir |
| `CHANGELOG.md` | ✅ Aparentemente al día | Verificar |
| `README.md` | ✅ Verificar | |
| `plan_delfos.md` | 🔵 Otro plan (mix install), no relacionado | Mantener separado |

---

## 2. Decisiones confirmadas por el usuario

Estas son las decisiones tomadas durante la sesión de auditoría. **No se revisan.**

### 2.1 Eliminar (alias muertos, duplicados, sin track + typo)

| Comando | Razón |
|---|---|
| ❌ `delfos watch` | Forwardea a `delfos mcp`. Es duplicado. **ELIMINADO inmediatamente**, sin alias.** |
| ❌ `delfos serve` | Idem. **ELIMINADO inmediatamente**, sin alias.** |
| ❌ `delfos preset` (top-level) | Existe `delfos config preset`. **ELIMINADO**, sin alias. |
| ❌ `delfos setup` (top-level) | Existe `delfos config setup`. **ELIMINADO**, sin alias. |
| ❌ `delfos models` (top-level) | Existe `delfos config models`. **ELIMINADO**, sin alias. |
| ❌ `delfos context` | Alias deprecado de `agents`. **ELIMINADO**, sin alias. |
| ❌ `delfos config wizard` | Alias de `delfos config setup llm`. **ELIMINADO**, sin alias. |
| ❌ `delfos config doctor` | Existe `delfos doctor` top-level. **ELIMINADO**, sin alias. |
| ❌ `delfos config probe` | Absorbido en `delfos doctor --summary` (o eliminar). **ELIMINADO**. |
| ❌ `delfos agents --symbol` | Muddling. Mover lógica a `delfos explain`. **Flag eliminado**. |
| ❌ `delfos stadistics` (typo) | Renombrar a `delfos status --stats` (flag). **Comando eliminado**, archivo borrado. |

### 2.2 Fusionar / renombrar

| Antes | Después | Razón |
|---|---|---|
| `delfos context` | `delfos agents` (sin `--symbol`) | Un solo comando, sin dualidad. |
| `delfos agents --symbol <name>` | `delfos explain <name>` | Mismo propósito; consolidar. |
| `delfos stadistics` (typo) | `delfos status --stats` (flag corto) | Usuario prefiere `--stats`. Módulo `Delfos.Statistics` se mantiene como dominio. |
| `lib/delfos/cli/commands/stadistics.ex` (typo) | Consolidar handler en `status.ex`. Eliminar el archivo. | Eliminar el archivo de typo. |

### 2.3 Mantener como están (decisiones explícitas)

| Comando | Razón |
|---|---|
| `delfos init` y `delfos scan` separados | Distintos lifecycles; init = primer registro, scan = re-indexar. User acepta mantenerlos. |
| `delfos audit` separado | Lectura pura, distinto side-effect. |
| `delfos query/explain/graph/summarize` como CLI + MCP | CLI para humanos, MCP para agentes. Ambos tienen propósito. |
| `delfos config preset` (top-level eliminado pero sub-command queda) | `config preset <name>` es one-liner para "I want OpenAI". |
| `delfos config init` separado de `delfos config preset` | init = crear fichero con defaults; preset = aplicar config de provider. |

### 2.4 Wizard de LLM y embeddings

**Decisión del usuario**: el wizard de embeddings pide DEMASIADO. Caparlo.

| Cambia | De | A |
|---|---|---|
| `setup/llm/external.ex` pregunta `embedding.model` y `embedding.dim` | 5 prompts sobre embeddings | **0 prompts** (inferir del LLM; `dim` es compile-time fixed) |
| `setup/llm/llama_cpp.ex` pide 10 cosas | 10 prompts | **2-3 prompts** (script path OR manual mínimo) |
| Embedding URL/api_key | Explícito | Inferir de LLM si provider es el mismo |
| Embedding dim | Pregunta | NUNCA preguntar; viene de `config/config.exs` (compile-time) |

### 2.5 Integraciones

**Decisión**: añadir `vscode` (alta prioridad) y mantener la lista actual. Considerar `windsurf`, `continue`, `claude-desktop`, `roo-code` solo si merecen la pena.

**Regla crítica del usuario**: "asegúrate de que las integraciones sean realmente correctas y que no rompan nada (aunque cada actualización lo cambien)". → Validar con tests + esquema versionado.

### 2.6 CLI 100% Alaja DSL

**Decisión**: eliminar el anti-pattern "argv round-trip" en los 18 handlers. Cada handler debe usar `run_with_opts(opts_map)` directamente.

### 2.7 Multi-Boot (init / scan / audit / summarize)

**Decisión**: NO fusionar, pero unificar flags comunes. Cada comando acepta `--llm-less`, `--workers`, `--output`, etc. donde tenga sentido.

### 2.8 Componentes Alaja

**Decisión**: explotar más Alaja:
- `Alaja.Components.MultiBar` — para `delfos init` multi-stage, `delfos scan` paralelo.
- `Alaja.Components.Wizard` — para setup wizards (más estructura).
- `Alaja.Components.Pulsar` — para tareas en background (init, scan, summarize).
- `Alaja.Components.AnimatedBar` — para tareas lineales con duración.
- `Alaja.Components.Timer` (si existe) — para mostrar tiempo de ejecución.

---

## 3. Análisis comando-por-comando (decisión final)

### 3.1 `delfos init [path] [--force] [--with-summary] [--with-briefing]`

| Campo | Valor |
|---|---|
| **Hace** | Registra proyecto, scan full, opcionalmente summary + briefing |
| **Usa embeddings** | Indirectamente (vía scan) |
| **Usa LLM** | Solo si `--with-summary` |
| **Estado** | ✅ Funcional |
| **Refactor** | Añadir flags `--force`, `--with-summary`, `--with-briefing`. Multi-stage progress con MultiBar (scan + summary + briefing). |
| **Archivo** | `lib/delfos/cli/commands/init.ex` |

### 3.2 `delfos scan [--full] [--workers N] [--llm-less]`

| Campo | Valor |
|---|---|
| **Hace** | Re-index incremental o full |
| **Usa embeddings** | Sí |
| **Usa LLM** | No (escaneo puro) |
| **Estado** | ✅ Funcional |
| **Refactor** | Añadir `--llm-less` (default false; salta embedding step si true — solo indexa, no vectoriza). |
| **Archivo** | `lib/delfos/cli/commands/scan.ex` |

### 3.3 `delfos query <text> [--kind K] [--level L] [-n N] [--format text|json] [--llm-less]`

| Campo | Valor |
|---|---|
| **Hace** | Hybrid search |
| **Usa embeddings** | Sí |
| **Usa LLM** | No |
| **Estado** | ✅ Funcional |
| **Refactor** | `--llm-less` para usar BM25+graph sin vector. |
| **Archivo** | `lib/delfos/cli/commands/query.ex` |

### 3.4 `delfos explain <name> [--fresh] [--no-cache] [--llm-less]`

| Campo | Valor |
|---|---|
| **Hace** | Muestra resumen cached o llama LLM |
| **Usa embeddings** | Sí (find_symbol) |
| **Usa LLM** | Sí |
| **Estado** | ✅ Funcional |
| **Refactor** | `--llm-less`: solo muestra info estática (signature, callers, callees, risk) sin resumen LLM. `--no-cache`: fuerza recarga del symbol. |
| **Archivo** | `lib/delfos/cli/commands/explain.ex` |

### 3.5 `delfos audit [--file path] [--with-explanation] [--llm-less]`

| Campo | Valor |
|---|---|
| **Hace** | Métricas de deuda |
| **Usa embeddings** | NO |
| **Usa LLM** | NO actualmente; **debería opcionalmente** |
| **Estado** | ⚠️ Funcional pero sub-aprovecha LLM |
| **Refactor** | `--with-explanation`: llama LLM para generar "diagnóstico narrativo" de los hotspots/deuda. `--llm-less`: comportamiento actual (solo números). |
| **Archivo** | `lib/delfos/cli/commands/audit.ex` |

### 3.6 `delfos summarize [--level N] [--force]`

| Campo | Valor |
|---|---|
| **Hace** | Genera resúmenes LLM |
| **Usa embeddings** | Sí (embed summaries L3) |
| **Usa LLM** | Sí |
| **Estado** | ⚠️ Usa `Task.async_stream` en vez de `Arrea.run_sync` |
| **Refactor** | Cambiar a `Arrea.run_sync(funs, workers: 5, timeout: 30_000)`. Pulsar para progreso. |
| **Archivo** | `lib/delfos/cli/commands/summarize.ex` |

### 3.7 `delfos graph <sub> <name> [--depth N]`

| Campo | Valor |
|---|---|
| **Hace** | `callers`, `callees`, `impact`, `cycles` |
| **Usa embeddings** | No |
| **Usa LLM** | No |
| **Estado** | ✅ Funcional |
| **Refactor** | Sin cambios. Quizás `--llm-explain` para `cycles`: LLM explica cada ciclo. |
| **Archivo** | `lib/delfos/cli/commands/graph.ex` |

### 3.8 `delfos agents [--output dir]`

| Campo | Valor |
|---|---|
| **Hace** | Genera `AGENTS.md` + `CLAUDE.md` |
| **Usa embeddings** | NO |
| **Usa LLM** | NO actualmente; **debería** (executive summary) |
| **Estado** | ⚠️ Solo con briefing estático |
| **Refactor** | Quitar `--symbol`. Añadir `--with-explanation` para que LLM genere un "executive summary" del proyecto al inicio del briefing. |
| **Archivo** | `lib/delfos/cli/commands/agents.ex` |

### 3.9 `delfos status [--statistics]`

| Campo | Valor |
|---|---|
| **Hace** | Imprime proyectos con métricas |
| **Usa embeddings** | NO |
| **Usa LLM** | NO |
| **Estado** | ⚠️ `stadistics` no trackeado, con typo |
| **Refactor** | Mover lógica de `Delfos.Statistics.usage_snapshot/1` a un flag `--statistics` aquí. Renombrar typo. |
| **Archivo** | `lib/delfos/cli/commands/status.ex` + borrar `lib/delfos/cli/commands/stadistics.ex` |

### 3.10 `delfos doctor [--fix] [--guided] [--json]`

| Campo | Valor |
|---|---|
| **Hace** | Diagnóstico de instalación |
| **Usa embeddings** | NO |
| **Usa LLM** | NO |
| **Estado** | ✅ Funcional |
| **Refactor** | Renombrar `--interactive` → `--guided` (más claro). Eliminar `--scope` interno (ahora va implícito). |
| **Archivo** | `lib/delfos/cli/commands/doctor.ex` |
| **Args** | `--fix`, `--guided`, `--json`, `--help`. **Mantener solo los que aportan.** |

### 3.11 `delfos config <subcommand>`

Sub-comandos tras refactor:

| Sub | Args | Acción |
|---|---|---|
| `show` | — | Mostrar config activa |
| `path` | — | Ruta del fichero |
| `init` | — | Crear config con defaults |
| `get <sec> <key>` | — | Leer valor |
| `set <sec> <key> <val>` | — | Escribir valor |
| `preset <name>` | — | Aplicar preset (local/anthropic/openai/openai-large) |
| `setup [db\|llm]` | — | Wizard interactivo |
| `models` | — | Mostrar providers activos |

**Elimina**: `wizard`, `doctor`, `probe` (mover a `delfos doctor`, `delfos probe` top-level o absorbido en status).

### 3.12 `delfos integrate <agent|all> [--yes] [--project path]`

| Campo | Valor |
|---|---|
| **Hace** | Configura AI agents |
| **Estado** | 🟡 Faltan integraciones |
| **Refactor** | Añadir `vscode`. Considerar `windsurf`, `continue`, `claude-desktop`, `roo-code`. |
| **Archivo** | `lib/delfos/cli/commands/integrate.ex` |

### 3.13 `delfos mcp`

Sin cambios. Es el servidor MCP canónico.

### 3.14 `delfos version`

Sin cambios.

---

## 4. Uso de modelos (Embeddings + LLM)

### 4.1 Matriz actual (lo que hace hoy)

| Comando | Embeddings | LLM (chat) | LLM (summarize) |
|---|---|---|---|
| `init` | indirecto | no | no |
| `scan` | ✅ sí | no | no |
| `query` | ✅ sí | no | no |
| `explain` | ✅ sí | ✅ sí | no |
| `summarize` | ✅ sí | no | ✅ sí |
| `audit` | no | no | no |
| `graph` | no | no | no |
| `agents` | no | no | no |
| `status` | no | no | no |
| `mcp` server | ✅ sí | ✅ sí | ✅ sí |
| `config` / `setup` / `doctor` / `integrate` | no | no | no |

### 4.2 Matriz propuesta (con `--llm-less`)

| Comando | `--llm-less` activo (default) | `--with-X` activo |
|---|---|---|
| `init` | register + scan + cache | `--with-summary` → chain summarize. `--with-briefing` → chain agents |
| `scan` | scan + embed (--llm-less no aplica) | n/a |
| `query` | BM25 + graph (sin vector) | (default) → + vector |
| `explain` | solo static info (signature, callers, callees, risk) | (default) → + LLM summary |
| `audit` | solo números | `--with-explanation` → + LLM diagnosis |
| `summarize` | (no aplica, es siempre LLM) | n/a |
| `graph` | graph query | `--llm-explain` → + LLM explanation per cycle |
| `agents` | static briefing | `--with-explanation` → + LLM executive summary |
| `status` | solo counts | `--statistics` → + MCP usage |

### 4.3 Plan de adopción por fase

| Fase | Comando | Cambio |
|---|---|---|
| A | `explain` | Añadir `--llm-less` flag (default true) |
| A | `query` | Añadir `--llm-less` flag (default false) |
| A | `scan` | Sin cambios (siempre embed) |
| B | `audit` | Añadir `--with-explanation` (LLM-powered diagnosis) |
| B | `agents` | Quitar `--symbol`. Añadir `--with-explanation` para executive summary |
| B | `graph cycles` | Añadir `--llm-explain` opcional |
| C | `init` | Añadir `--with-summary` + `--with-briefing` |
| C | `status` | Añadir `--statistics` (migrar stadistics) |
| C | `init --llm-less` | "register + scan, sin embeddings ni summary" — solo skeleton |

---

## 5. Uso del ecosistema — gaps detectados

### 5.1 Apero — uso correcto

| Función | Usada en | Notas |
|---|---|---|
| `Apero.Http.post/get` | llm/client.ex, setup/llm/* | OK |
| `Apero.Http.Finch.ensure_started/0` | application.ex:29, init.ex:80 | Doble llamada pero defendible (init via `eval`) |
| `Apero.Retry.with/2` | llm/client.ex | **Refactor candidato** → Arrea.CircuitBreaker |
| `Apero.Crypto.Cipher.encrypt/decrypt` | manager.ex:564, 598 | OK; REMAINING_TASKS §3.1 miente (sigue delegado) |
| `:crypto.strong_rand_bytes/1` | manager.ex:541 | OK (KDF primitivo) |
| `:crypto.hash(:sha256/:md5, ...)` | file_processor.ex:337, summarize.ex:162 | OK (hashing primitivo) |

**Gap**: `Apero.Proc.which/1`, `Apero.Proc.command_exists?/1` NO se usan — hay 4 `System.find_executable` directos.

### 5.2 Arrea — uso correcto con 2 gaps

| Función | Usada en | Notas |
|---|---|---|
| `Arrea.run_sync/2` | hybrid_search.ex, file_processor.ex | ✅ Fachada pública |
| `Arrea.Command.execute/2` | graph_builder.ex | ✅ |
| `Arrea.LongRunning.start_link/3` | llm_discovery.ex | ✅ |
| `Arrea.Subscribers` | mcp/index_broadcaster.ex | ✅ |
| `Arrea.CircuitBreaker.execute/2` | (ningún uso) | ❌ Falta. Refactor de `Apero.Retry.with` |
| `Arrea.Policy`, `Arrea.Rules` | (ningún uso) | — No se requieren ahora |

**Gap 1**: `summarize.ex:106` usa `Task.async_stream` directo. Refactor a `Arrea.run_sync`.
**Gap 2**: `Apero.Retry.with` en `llm/client.ex` debería ser `Arrea.CircuitBreaker.execute` (más rico).

### 5.3 Trebejo — uso parcial, 24 bypasses

| Función | Usada en | Notas |
|---|---|---|
| `Trebejo.Git.Local.churn/2` | analysis/churn_analyzer.ex | ✅ |
| `Trebejo.Docker` | config/postgres_discovery/installer.ex | ✅ |
| `Trebejo.Network` | config/postgres_discovery/installer.ex | ✅ |
| `Trebejo.Util` | cli/commands/init.ex | ✅ |
| `Trebejo.Proc`, `Trebejo.Packages` | (ningún uso) | ❌ |

**Bypass**: 24 `System.cmd/3` directos:
- `setup/db.ex`: 14 (docker ps, brew install, createdb, etc.) → debería ser `Trebejo.Docker`
- `setup/llm/llama_cpp.ex`: 4 (llama-server --version)
- `config/llm_discovery.ex`: 3 (nvidia-smi)
- `config/postgres_discovery.ex`: 2 (`System.find_executable`)
- `integrate.ex`: 1 (`System.find_executable`)

**Refactor prioritario**: `setup/db.ex` → usar `Trebejo.Docker` (consistencia con `installer.ex`).

### 5.4 Candil — bien usado

`Candil.chat/4`, `Candil.embed/3`, `Candil.Health.probe/2`, `Candil.HTTP.get/3`, `Candil.Config.register_*`, `Candil.Error`. Todo en uso correcto.

### 5.5 Botica — activo (mentira del audit previo corregida)

| Función | Archivo |
|---|---|
| `Botica.Doctor.run/1` | diagnostics.ex:51, health.ex:53 |
| `Botica.Doctor.fix/1` | doctor.ex:131 |
| `Botica.Repair.Fixer.fix_one/2` | doctor.ex:200 |

`audit_delfos.txt` dijo "dead code" → **FALSO**. Botica está vivo y bien usado.

### 5.6 Alaja — uso correcto, falta explotar componentes visuales

| Componente | Usado | Notas |
|---|---|---|
| `Alaja.CLI.Definition` DSL | cli.ex | ✅ |
| `Alaja.print_*` | muchos | ✅ |
| `Alaja.Components.Table` | cli.ex:478 | ✅ |
| `Alaja.Components.Header` | setup/*.ex | ✅ |
| `Alaja.Components.Progress` (single-bar) | file_processor.ex | ✅ |
| `Alaja.Components.MultiBar` | NO usado | ❌ Oportunidad: delfos init multi-stage |
| `Alaja.Components.AnimatedBar` | NO usado | ❌ Oportunidad: scan con archivo actual |
| `Alaja.Components.Pulsar` | NO usado | ❌ Oportunidad: tareas en background (mcp server start, scan, init) |
| `Alaja.Components.Wizard` | NO usado | ❌ Oportunidad: setup wizards |
| `Alaja.Components.Box`, `Separator`, `Breadcrumbs` | Parcial | Refactor visual |
| `Alaja.Components.Timer` (si existe) | NO usado | ❌ Oportunidad: duración de init, scan, summarize |

---

## 6. Estructura CLI target

### 6.1 Comandos top-level (limpio)

```
delfos                                # global help
delfos --help | -h | --version | -v   # global flags
delfos init [path] [--force] [--with-summary] [--with-briefing]
delfos scan [--full] [--workers N] [--llm-less]
delfos query <text> [--kind K] [--level L] [-n N] [--format text|json] [--llm-less]
delfos explain <name> [--fresh] [--no-cache] [--llm-less]
delfos audit [--file path] [--with-explanation] [--llm-less]
delfos summarize [--level N] [--force]
delfos graph <callers|callees|impact|cycles> <name> [--depth N] [--llm-explain]
delfos agents [--output dir] [--with-explanation]
delfos status [--statistics]
delfos doctor [--fix] [--guided] [--json]
delfos config <subcommand>           # ver §6.2
delfos integrate <agent|all> [--yes] [--project path]
delfos mcp
delfos version
```

**Total: 14 comandos top-level.** Limpio, no redundante.

### 6.2 Sub-comandos de `delfos config`

```
delfos config show
delfos config path
delfos config init
delfos config get <section> <key>
delfos config set <section> <key> <value>
delfos config preset <name>
delfos config setup [db|llm]
delfos config models
```

### 6.3 Sub-comandos de `delfos integrate`

**Lista final de 10 agentes** (ordenada por popularidad/adopción):

```
delfos integrate claude-code      # ya existía
delfos integrate claude-desktop   # NUEVO (v2.3.0)
delfos integrate opencode         # ya existía
delfos integrate cursor           # ya existía
delfos integrate vscode           # NUEVO (v2.3.0)
delfos integrate continue         # NUEVO (v2.3.0)
delfos integrate windsurf         # NUEVO (v2.3.0)
delfos integrate roo-code         # NUEVO (v2.3.0)
delfos integrate aider            # ya existía
delfos integrate codex            # ya existía
delfos integrate zed              # ya existía
delfos integrate all
```

### 6.4 Aliases deprecados — **NINGUNO se mantiene**

Por decisión del usuario (2026-07-15): todo alias deprecado es **deuda técnica**. Se eliminan inmediatamente, sin período de gracia, sin warning.

| Eliminado | Razón |
|---|---|
| `delfos watch` | Duplica `delfos mcp`. Sin valor. |
| `delfos serve` | Duplica `delfos mcp`. Sin valor. |
| `delfos context` | Alias de `agents`. Sin valor. |
| `delfos preset` (top-level) | `delfos config preset` ya existe. |
| `delfos setup` (top-level) | `delfos config setup` ya existe. |
| `delfos models` (top-level) | `delfos config models` ya existe. |
| `delfos config wizard` | Alias de `config setup llm`. |
| `delfos config doctor` | `delfos doctor` top-level ya existe. |
| `delfos config probe` | Absorbido en `delfos doctor --summary`. |
| `delfos agents --symbol` | Mover a `delfos explain`. |
| `delfos stadistics` | Renombrar a `delfos status --stats`. |

---

## 7. Plan de tareas detallado (24 tareas, 4 fases)

### FASE A — Quick Wins (1 sesión de coder, ~3h)

| # | Tarea | Archivos | Esfuerzo |
|---|---|---|---|
| A1 ✅ | Eliminar comandos duplicados del `cli.ex`: `watch`, `serve`, `preset`, `setup`, `models` (top-level). Solo dejar declaraciones deprecation si se decide mantener como alias. | `lib/delfos/cli.ex` | 30min |
| A2 ✅ | Eliminar `delfos context` command y handler. | `lib/delfos/cli.ex` | 5min |
| A3 ✅ | Eliminar `delfos config wizard` y `delfos config doctor` sub-comandos. | `lib/delfos/cli/commands/config.ex` | 15min |
| A4 ✅ | Refactor `delfos config show` para mostrar también `[mcp]` section (si existe). | `lib/delfos/cli/commands/config.ex` | 10min |
| A5 ✅ | Refactor `summarize.ex:106` `Task.async_stream` → `Arrea.run_sync(funs, workers: 5, timeout: 30_000)`. | `lib/delfos/cli/commands/summarize.ex` | 15min |
| A6 ✅ | Reemplazar 4 `System.find_executable` directos con `Apero.Proc.which/1`. | `config/postgres_discovery.ex`, `integrate.ex` | 30min |
| A7 ✅ | Renombrar flag `--interactive` → `--guided` en doctor. Actualizar tests. | `lib/delfos/cli/commands/doctor.ex`, `test/delfos/cli/commands/doctor_test.exs` | 15min |

### FASE B — Refactor estructural (1-2 sesiones, ~6h)

| # | Tarea | Archivos | Esfuerzo |
|---|---|---|---|
| B1 ✅ | Eliminar argv-round-trip en los 18 handlers de `cli.ex`. Cada handler llama `run_with_opts(opts)` directo. | `lib/delfos/cli.ex` | 3h |
| B2 ✅ | Eliminar 9 `Alaja.CLI.OptionsParser.parse` manuales. Cada `Commands.X.run/1` queda solo para back-compat con scripts externos. | `agents.ex`, `doctor.ex`, `explain.ex`, `graph.ex`, `integrate.ex`, `query.ex`, `scan.ex`, `stadistics.ex`, `summarize.ex` | 2h |
| B3 ✅ | Quitar `--symbol` de `delfos agents`. Mover lógica a `delfos explain` (que ya hace eso). | `agents.ex`, `cli.ex`, test | 30min |
| B4 ✅ | Mover `Delfos.Statistics.usage_snapshot/1` y `index_snapshot/1` a un flag `--statistics` de `delfos status`. Eliminar el comando `stadistics` y su archivo con typo. | `status.ex`, `stadistics.ex` (delete), `statistics.ex` (queda como módulo de dominio), `cli.ex` | 1h |
| B5 ✅ | Reorganizar sub-comandos de `delfos config` (dejar solo los 8 listados en §6.2). Eliminar `wizard`, `doctor`, `probe` (top-level ya existe). | `config.ex` | 1h |
| B6 ✅ | Sistema uniforme de `--help` por comando. Crear helper `Alaja.Help.print/2` que renderiza `@help` block via Alaja. Cada comando define su `@help` completo (con examples). | `cli.ex`, todos los commands | 4h |
| B7 ✅ | Añadir flag `--llm-less` a `query`, `explain`, `audit`. | `query.ex`, `explain.ex`, `audit.ex` | 30min |
| B8 ✅ | Añadir flag `--with-explanation` (LLM) a `audit` y `agents`. Implementar `Delfos.Audit.Narrative.generate/1` que produce diagnóstico en prosa con cita de hotspots. | `audit.ex`, `agents.ex`, `lib/delfos/audit/narrative.ex` (nuevo) | 2h |

### FASE C — Ecosystem migration (1-2 sesiones, ~8h)

| # | Tarea | Archivos | Esfuerzo |
|---|---|---|---|
| C1 ❌ | Reemplazar `Apero.Retry.with` en `llm/client.ex` con `Arrea.CircuitBreaker.execute/2` (configuración: 3 attempts, 1s base, 10s max, retry on 5xx/429). | `llm/client.ex`, `arrea.ex` config | 2h |
| C2 ✅ | Refactor `setup/db.ex`: reemplazar 14 `System.cmd("docker", ...)` con `Trebejo.Docker`. | `cli/commands/setup/db.ex` | 2h |
| C3 ❌ | Reemplazar `bash -c "$cmd"` (shell injection risk) en `setup/db.ex:405` con `Trebejo.SafeCommand.execute/2` o `arg: list` mode. | `cli/commands/setup/db.ex` | 1h |
| C4 ❌ | Refactor `setup/llm/llama_cpp.ex`: reducir 10 prompts a 2-3 (script path OR manual mínimo). | `cli/commands/setup/llm/llama_cpp.ex` | 3h |
| C5 ❌ | Refactor `setup/llm/external.ex`: NO preguntar embedding model ni dim. Inferir del LLM. | `cli/commands/setup/llm/external.ex` | 2h |
| C6 ❌ | Auto-arranque del embedding server. `Delfos.Config.LLMDiscovery.ensure_embedding_server/0` que arranca llama-server si no está. Llamado desde `delfos init`, `delfos doctor --fix`. | `lib/delfos/config/llm_discovery.ex`, `lib/delfos/cli/commands/init.ex` | 2h |
| C7 ❌ | Usar `Alaja.Components.MultiBar` en `delfos init` para mostrar scan + summary + briefing simultáneamente. | `init.ex` (con `MultiBar.new/2`) | 1h |
| C8 ❌ | Usar `Alaja.Components.Pulsar` para `delfos mcp` startup (tareas en background). | `mcp/server.ex` | 30min |
| C9 ❌ | Usar `Alaja.Components.AnimatedBar` + `Timer` para `delfos scan` (muestra archivo actual + tiempo estimado). | `scan.ex`, `file_processor.ex` | 1h |
| C10 ❌ | Usar `Alaja.Components.Wizard` para `setup` wizards (estructura unificada). | `setup.ex`, `setup/llm.ex`, `setup/db.ex` | 2h |

### FASE D — Integraciones + polish (1-2 sesiones, ~6h)

| # | Tarea | Archivos | Esfuerzo |
|---|---|---|---|
| D1 ✅ | Añadir `delfos integrate vscode`. Configura `.vscode/mcp.json` con la spec MCP (command, args, type, enabled). Verificar formato con VSCode 1.85+. | `integrate.ex`, `test/delfos/cli/commands/integrate_test.exs` | 1h |
| D2 ✅ | Validar y reforzar las 6 integraciones existentes con tests que verifiquen el JSON generado contra el esquema oficial del agente. | `integrate.ex`, `integrate_formats_test.exs` | 2h |
| D3 ✅ | Considerar añadir `windsurf`, `continue`, `claude-desktop`, `roo-code` (solo si el usuario lo pide). | `integrate.ex` | 1h |
| D4 ✅ | Sincronizar `SPEC.md`, `LLM_USAGE.md`, `MCP_TOOLS.md`, `README.md` con la nueva estructura CLI. | docs/* | 4h |
| D5 ✅ | Reemplazar la `botica dead code` mentira en `audit_delfos.txt`. Marcar como histórico o archivar. | `audit_delfos.txt` | 5min |
| D6 ✅ | Actualizar `REMAINING_TASKS.md` §3.1 (crypto: dice "inline" pero sigue siendo `Apero.Crypto.Cipher`). | `REMAINING_TASKS.md` | 10min |

---

## 8. Refactors por archivo

### 8.1 `lib/delfos/cli.ex` — main entry, dispatch

| Cambio | Detalle |
|---|---|
| Eliminar 6 commands deprecados | `watch`, `serve`, `preset`, `setup`, `models`, `context`. Si se decide mantener como alias con warning: marcar con `deprecate: true` flag en DSL. |
| Eliminar argv-round-trip en handlers | Cada handler recibe opts map completo y llama `Commands.X.run_with_opts(opts)`. |
| Mejorar `show_general_help/0` | Listar command + description + flags + examples (1 línea cada uno). |
| Añadir `pulsar` para startup | `delfos mcp` arranca con Pulsar en stderr mientras espera primer mensaje JSON-RPC. |

### 8.2 `lib/delfos/cli/commands/agents.ex`

| Cambio | Detalle |
|---|---|
| Quitar `--symbol` flag | Mover lógica a `delfos explain`. |
| Añadir `--with-explanation` | Llamar LLM para generar "executive summary" al inicio del briefing. |
| Quitar OptionsParser manual | Usar args de DSL via handler. |

### 8.3 `lib/delfos/cli/commands/audit.ex`

| Cambio | Detalle |
|---|---|
| Añadir `--with-explanation` | Llamar `Delfos.Audit.Narrative.generate(project)`. |
| Añadir `--llm-less` | (default) comportamiento actual. |

### 8.4 `lib/delfos/cli/commands/config.ex`

| Cambio | Detalle |
|---|---|
| Quitar `wizard`, `doctor`, `probe` sub-comandos | Mover a top-level. |
| Quitar OptionsParser manual | Handler directo. |
| Documentar `@help` block completo con examples | |

### 8.5 `lib/delfos/cli/commands/doctor.ex`

| Cambio | Detalle |
|---|---|
| Renombrar `--interactive` → `--guided` | Más claro. |
| Quitar OptionsParser manual | Handler directo. |
| Mejorar `--fix` | Mostrar progreso de reparación con AnimatedBar. |

### 8.6 `lib/delfos/cli/commands/explain.ex`

| Cambio | Detalle |
|---|---|
| Quitar OptionsParser manual | |
| Añadir `--llm-less` | (default true; user debe usar `--no-llm-less` para forzar LLM) |
| Añadir `--no-cache` | Fuerza recarga sin usar `symbol.summary`. |
| Absorber lógica de `agents --symbol` | Cuando se llama con symbol name, redirige aquí. |

### 8.7 `lib/delfos/cli/commands/graph.ex`

| Cambio | Detalle |
|---|---|
| Quitar OptionsParser manual | |
| Añadir `--llm-explain` (en `cycles`) | LLM explica cada SCC. |

### 8.8 `lib/delfos/cli/commands/init.ex`

| Cambio | Detalle |
|---|---|
| Quitar OptionsParser manual | |
| Añadir `--force` | Re-registro con wipe. |
| Añadir `--with-summary` | Chain summarize tras scan. |
| Añadir `--with-briefing` | Chain agents tras scan. |
| Añadir `--llm-less` | Solo register + scan + skeleton, sin embeddings. |
| Usar MultiBar para mostrar scan + summary + briefing en paralelo | |

### 8.9 `lib/delfos/cli/commands/integrate.ex`

| Cambio | Detalle |
|---|---|
| Añadir `vscode` agent | (ver §11) |
| Reforzar tests de validación | Cada agent valida el JSON generado contra schema real. |
| Considerar `windsurf`, `continue`, `claude-desktop`, `roo-code` | Si user aprueba. |

### 8.10 `lib/delfos/cli/commands/query.ex`

| Cambio | Detalle |
|---|---|
| Quitar OptionsParser manual | |
| Añadir `--llm-less` | BM25 + graph sin vector. |

### 8.11 `lib/delfos/cli/commands/scan.ex`

| Cambio | Detalle |
|---|---|
| Quitar OptionsParser manual | |
| Usar AnimatedBar + Timer para feedback | |
| No tocar `Task.async_stream` aquí (no hay) | |

### 8.12 `lib/delfos/cli/commands/stadistics.ex` (typo) — ELIMINAR

| Cambio | Detalle |
|---|---|
| Borrar archivo | |
| Eliminar handler `stadistics_handler/1` de `cli.ex` | |
| Eliminar `command "stadistics", ...` de `cli.ex` | |

### 8.13 `lib/delfos/cli/commands/status.ex`

| Cambio | Detalle |
|---|---|
| Añadir `--statistics` flag | Mostrar MCP usage + KB stats cuando se pase. |
| Reusar `Delfos.Statistics.usage_snapshot/1` | (que sigue existiendo como módulo de dominio). |

### 8.14 `lib/delfos/cli/commands/summarize.ex`

| Cambio | Detalle |
|---|---|
| Quitar OptionsParser manual | |
| `Task.async_stream` → `Arrea.run_sync` | |
| Usar Pulsar para feedback en tiempo real | |

### 8.15 `lib/delfos/cli/commands/setup/llm/llama_cpp.ex` (627 líneas)

| Cambio | Detalle |
|---|---|
| Reducir 10 prompts a 2-3 | Script path OR (endpoint, model path, api_key). |
| Quitar preguntas redundantes (gguf_dir, context_size, launcher, extra_args por defecto) | |
| Si embeddings target, NO preguntar — usar compile-time defaults | |

### 8.16 `lib/delfos/cli/commands/setup/llm/external.ex` (303 líneas)

| Cambio | Detalle |
|---|---|
| Quitar embedding model y dim prompts | Inferir del LLM. |
| Solo preguntar: URL, API key, chat model | |
| Si target es `:both` o `:embedding` con OpenAI/Anthropic, el embedding provider es el mismo | |

### 8.17 `lib/delfos/cli/commands/setup/llm/ollama.ex` (241 líneas)

| Cambio | Detalle |
|---|---|
| Quitar `detect_ollama_dim` (compile-time) | |
| Si embeddings target, preguntar: ¿mismo Ollama server o distinto? | |

### 8.18 `lib/delfos/cli/commands/setup/db.ex` (720 líneas)

| Cambio | Detalle |
|---|---|
| Reemplazar `System.cmd("docker", ...)` con `Trebejo.Docker.run/1`, `Trebejo.Docker.start/1`, etc. | |
| Quitar `bash -c "$cmd"` (shell injection risk) | |
| Usar `Apero.Proc.command_exists?/1` para detectar psql, brew, apt-get | |

### 8.19 `lib/delfos/cli/llm_guard.ex`

| Cambio | Detalle |
|---|---|
| Añadir `"stadistics" => %{need: :none}` — DELETE (comando eliminado) | |
| Actualizar `"agents"` requirements | Sin `--symbol`, sin cambios. |
| Actualizar `"status"` requirements | Si `--statistics`, requiere DB. |

### 8.20 `lib/delfos/llm/client.ex`

| Cambio | Detalle |
|---|---|
| `Apero.Retry.with` → `Arrea.CircuitBreaker.execute` | |

### 8.21 `lib/delfos/config/manager.ex`

| Cambio | Detalle |
|---|---|
| Verificar `migrate_from_toml/0` sigue siendo útil (probablemente ya no, dado v2.x). Considerar eliminar. | |

### 8.22 `lib/delfos/config/llm_discovery.ex`

| Cambio | Detalle |
|---|---|
| Añadir `ensure_embedding_server/0` | Arranca llama-server si no está. |
| `Apero.Proc.which/1` en lugar de `System.find_executable("nvidia-smi")` | |

### 8.23 `lib/delfos/config/postgres_discovery.ex`

| Cambio | Detalle |
|---|---|
| `Apero.Proc.which/1` en lugar de `System.find_executable("docker")` | |

---

## 9. Tests a añadir/modificar

### 9.1 Tests nuevos (FASE A-C)

| Test | Archivo |
|---|---|
| `test/delfos/cli/commands/agents_test.exs` — quitar `--symbol` tests, añadir `--with-explanation` | |
| `test/delfos/cli/commands/audit_test.exs` — `--with-explanation`, `--llm-less` | |
| `test/delfos/cli/commands/explain_test.exs` — `--llm-less`, `--no-cache`, absorción de `agents --symbol` | |
| `test/delfos/cli/commands/init_test.exs` — `--force`, `--with-summary`, `--with-briefing` | |
| `test/delfos/cli/commands/query_test.exs` — `--llm-less` | |
| `test/delfos/cli/commands/status_test.exs` — `--statistics` (absorbe stadistics_test.exs) | |
| `test/delfos/cli/commands/integrate_formats_test.exs` — añadir `vscode` schema test | |
| `test/delfos/cli/cli_test.exs` — verificar aliases deprecados | |
| `test/delfos/cli/commands/config_test.exs` — quitar `wizard`, `doctor`, `probe` tests | |

### 9.2 Tests a eliminar

| Archivo | Razón |
|---|---|
| `test/delfos/cli/commands/stadistics_test.exs` | Comando eliminado |
| `test/delfos/cli/commands/context_test.exs` (si existe) | Comando eliminado |

### 9.3 Tests integración a actualizar

`test/delfos/integration_test.exs` (T15.2 fix, etc.). `mix test --include integration` debe pasar en CI.

---

## 10. Documentación a sincronizar

### 10.1 `docs/SPEC.md`

- Reemplazar header v0.5 con v2.3.0
- §10.2: nueva lista de comandos (14 top-level)
- §10.3: tabla de output visual actualizada
- §11.1: aclarar path (`~/.config/delfos/config.json`)
- §13: CLI reference completa
- §13.1 añadir `delfos explain <name>` como equivalente a MCP `delfos_symbol`
- §3.1: añadir schema `mcp_usage_events`
- §6: matizar que el modelo de embedding es compile-time-fixed
- §13.6: confirmar que `embedding.dim` no es editable en runtime

### 10.2 `docs/MCP_TOOLS.md`

- §1: cambiar `delfos serve --mcp` por `delfos mcp`
- §MCP_TOOLS: añadir tool nueva si existe (verificar)

### 10.3 `docs/LLM_USAGE.md`

- §1: cambiar "1024-dim" → dim actual (1536)
- Tabla: añadir columna `--llm-less` por comando
- Eliminar `delfos watch` (ya no es comando)
- Actualizar `delfos context` → `delfos agents`
- Añadir `delfos status --statistics`

### 10.4 `docs/HANDOFF.md`

- §1: limpiar cuentas OSS vs privados
- §19: arch paths actualizados
- §14: actualizar bug list cerrado

### 10.5 `docs/REMAINING_TASKS.md`

- §3.1: corregir (crypto NO está inline, sigue en `Apero.Crypto.Cipher`)
- §3.11-15: marcar cerrado
- Añadir "FASE A-D" como §16-19 con las tareas de este plan

### 10.6 `docs/SESSION_STATE.md`

- Header: actualizar a v2.3.0 (cuando taggeamos)
- Open issues: Bug #25 (callers/callees empty) sigue abierto
- Cerrar issues resueltos

### 10.7 `docs/NEXT_PHASE.md`

- Marcar como histórico (la fase §7.1-7.6 ya está cerrada)
- Crear `docs/REFACTOR_PLAN.md` (este doc) como nuevo "NEXT_PHASE"

### 10.8 `docs/TEST_PLAN.md`

- Marcar T16 cerrado
- Cerrar T20 (watch deprecado)
- Cerrar T22 (edge cases) si pasan
- T21 ya está documentado en REMAINING_TASKS

### 10.9 `audit_delfos.txt`

- Botica "dead code" → **BORRAR** o corregir (Botica es vivo)
- Otras secciones pueden quedar si aún son válidas

### 10.10 `README.md` + `README.es.md`

- Tabla de comandos actualizada
- Sección "Integrations" listando agentes
- Quitar menciones a `serve --mcp`

### 10.11 `CHANGELOG.md`

- Entrada `[2.3.0]` con todos los cambios
- `BREAKING`: eliminación de `serve`, `watch`, `context`, `preset` top-level, `setup` top-level, `models` top-level, `wizard`, `config doctor`, `config probe`, `stadistics` (typo), `agents --symbol`

---

## 11. Integración `vscode` (especificación)

### 11.1 VSCode MCP config schema

```json
{
  "servers": {
    "delfos": {
      "type": "stdio",
      "command": "delfos",
      "args": ["mcp"]
    }
  }
}
```

### 11.2 Path del fichero

- Global: `~/.config/Code/User/mcp.json` o `~/.vscode/argv.json` (Windows)
- Workspace: `.vscode/mcp.json` (recomendado para proyecto)

### 11.3 Implementación

```elixir
defp configure_agent("vscode", project_path) do
  mcp_path = Path.join(project_path, ".vscode", "mcp.json")
  File.mkdir_p!(Path.dirname(mcp_path))
  
  config = %{
    "servers" => %{
      "delfos" => %{
        "type" => "stdio",
        "command" => delfos_bin(),
        "args" => ["mcp"]
      }
    }
  }
  
  safe_write(mcp_path, Jason.encode!(config, pretty: true))
  :ok
end
```

### 11.4 Tests

- Verificar que `safe_write/2` no rompe config existente (merge con servers existentes).
- Verificar schema (debe tener `servers.delfos.type`, `command`, `args`).
- Test en `integrate_formats_test.exs`.

---

## 12. Criterios de aceptación

### 12.1 FASE A — Done when

- [ ] `cli.ex` no declara: `watch`, `serve`, `preset`, `setup`, `models` (top-level), `context`, `stadistics`, `agents --symbol`.
- [ ] `summarize.ex:106` usa `Arrea.run_sync`.
- [ ] 4 `System.find_executable` reemplazados por `Apero.Proc.which/1`.
- [ ] `mix compile --warnings-as-errors` limpio.
- [ ] `mix test` 100% pass.

### 12.2 FASE B — Done when

- [ ] Los 18 handlers de `cli.ex` llaman `run_with_opts(opts)` directo (sin argv round-trip).
- [ ] 9 archivos eliminan `Alaja.CLI.OptionsParser.parse`.
- [ ] `delfos agents` sin `--symbol`. `delfos explain <name>` absorbe esa lógica.
- [ ] `delfos status --statistics` funciona. `delfos stadistics` eliminado.
- [ ] `delfos config` tiene 8 sub-comandos limpios.
- [ ] Todos los commands tienen `@help` block uniforme con examples.
- [ ] `--llm-less` funciona en `query`, `explain`, `audit`.
- [ ] `--with-explanation` funciona en `audit`, `agents`.
- [ ] `mix test` + `mix dialyzer` clean.

### 12.3 FASE C — Done when

- [ ] `Apero.Retry.with` reemplazado por `Arrea.CircuitBreaker.execute` en `llm/client.ex`.
- [ ] `setup/db.ex` usa `Trebejo.Docker` para todas las llamadas docker.
- [ ] `bash -c "$cmd"` reemplazado por `arg: list`.
- [ ] `setup/llm/llama_cpp.ex` pide max 3 prompts (no 10).
- [ ] `setup/llm/external.ex` no pregunta embedding model/dim.
- [ ] `ensure_embedding_server/0` arranca llama-server si down.
- [ ] `init` muestra MultiBar (scan + summary + briefing).
- [ ] `mcp` startup usa Pulsar.
- [ ] `scan` usa AnimatedBar + Timer.
- [ ] Setup wizards usan `Alaja.Components.Wizard`.

### 12.4 FASE D — Done when

- [ ] `delfos integrate vscode` funcional y testeado.
- [ ] Las 6 integraciones existentes validadas con tests de schema.
- [ ] SPEC.md, LLM_USAGE.md, MCP_TOOLS.md, README.md sincronizados con nueva estructura.
- [ ] `audit_delfos.txt` corregido (Botica no es dead code).
- [ ] CHANGELOG.md con entry `[2.3.0]`.
- [ ] `mix docs` genera docs ExDoc correctamente (con `source_ref: "2.3.0"`).
- [ ] `mix gen && delfos doctor` todo verde.

---

## 13. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Eliminar un comando rompe scripts externos | Alta | Media | Mantener como deprecation alias en v2.3.x, eliminar en v3.0 |
| Refactor de argv-round-trip rompe tests | Media | Alta | Hacer refactor + tests en mismo commit; usar git bisect |
| Auto-arranque llama-server mata proceso de usuario | Media | Alta | Usar `Candil` engine lifecycle o `Arrea.LongRunning` (manejado) |
| Cambio en `--interactive` → `--guided` rompe docs externas | Baja | Baja | Mantener ambos como alias |
| Cambio de dim a 1536 rompe índices viejos | Baja | Alta | Ya hay migración `20260715000002_fix_vector_dim_to_1536` |

---

## 14. Orden de ejecución recomendado

```
FASE A (Quick Wins, 1 sesión)
├── A1, A2, A3 (eliminar duplicados)   [1h]
├── A5 (summarize Arrea)              [15min]
├── A6 (Apero.Proc.which)             [30min]
├── A7 (doctor --guided)              [15min]
└── A4 (config show +mcp section)     [10min]
   ↓ tests + commit
FASE B (Estructural, 1-2 sesiones)
├── B1 (eliminar argv round-trip)     [3h]
├── B2 (eliminar OptionsParser manual)[2h]
├── B3 (agents --symbol removal)      [30min]
├── B4 (stadistics → status)          [1h]
├── B5 (config reorganize)            [1h]
├── B6 (uniforme help system)         [4h]
├── B7 (--llm-less flags)             [30min]
├── B8 (--with-explanation)           [2h]
   ↓ tests + commit
FASE C (Ecosystem migration, 1-2 sesiones)
├── C1 (Apero.Retry → Arrea.CB)       [2h]
├── C2 (Trebejo.Docker en setup/db)   [2h]
├── C3 (SafeCommand shell injection)  [1h]
├── C4 (llama_cpp wizard simplificado)[3h]
├── C5 (external wizard simplificado) [2h]
├── C6 (auto-arranque embed server)   [2h]
├── C7-C10 (Alaja components)         [4-5h]
   ↓ tests + commit
FASE D (Integrations + docs, 1-2 sesiones)
├── D1 (vscode integration)           [1h]
├── D2 (validar integraciones)        [2h]
├── D3 (considerar windsurf/continue) [1h]
├── D4 (sincronizar docs)             [4h]
├── D5 (corregir audit_delfos.txt)    [5min]
├── D6 (corregir REMAINING_TASKS.md)  [10min]
   ↓ tests + commit
FINAL
├── tag v2.3.0
├── mix gen && delfos doctor (smoke test)
└── cherry-pick a main, push
```

**Estimación total**: 5-7 sesiones de coder (cada sesión ~3-4h) + 1 sesión de documentador.

---

## 15. Aliases que se mantienen tras Fase A (con deprecation warning)

Decisión: ¿mantener los aliases deprecados durante v2.3.x y eliminar en v3.0?

| Alias | Forward | Razón para mantener |
|---|---|---|
| `delfos watch` | `mcp` | muscle memory de usuarios |
| `delfos serve` | `mcp` | docs antiguas pueden tener |
| `delfos context` | `agents` | scripts externos |

**Aliases que SÍ se eliminan inmediatamente** (no son deprecation worthy):
- `delfos preset` (top-level) → `config preset`
- `delfos setup` (top-level) → `config setup`
- `delfos models` (top-level) → `config models`
- `delfos config wizard` → `config setup llm`
- `delfos config doctor` → `doctor`
- `delfos config probe` → absorbido en `doctor --summary` (o eliminar)
- `delfos stadistics` (typo) → `status --statistics`
- `delfos agents --symbol` → `explain <name>`

---

## 16. Apéndice A — Inventario de archivos a tocar

### 16.1 Archivos a MODIFICAR (no eliminar)

```
lib/delfos/cli.ex                                       # handlers, commands, help
lib/delfos/cli/llm_guard.ex                            # requirements map
lib/delfos/cli/commands/agents.ex                      # remove --symbol, add --with-explanation
lib/delfos/cli/commands/audit.ex                       # add --with-explanation, --llm-less
lib/delfos/cli/commands/config.ex                      # remove wizard/doctor/probe, restructure
lib/delfos/cli/commands/doctor.ex                      # --guided, remove manual OptionsParser
lib/delfos/cli/commands/explain.ex                     # --llm-less, --no-cache, absorb agents --symbol
lib/delfos/cli/commands/graph.ex                        # --llm-explain (cycles)
lib/delfos/cli/commands/init.ex                        # --force, --with-summary, --with-briefing, --llm-less, MultiBar
lib/delfos/cli/commands/integrate.ex                   # add vscode, remove manual OptionsParser
lib/delfos/cli/commands/query.ex                       # --llm-less, remove manual OptionsParser
lib/delfos/cli/commands/scan.ex                        # AnimatedBar, remove manual OptionsParser
lib/delfos/cli/commands/status.ex                      # --statistics, absorb stadistics
lib/delfos/cli/commands/summarize.ex                   # Arrea.run_sync, remove manual OptionsParser
lib/delfos/cli/commands/setup.ex                       # Alaja.Wizard
lib/delfos/cli/commands/setup/db.ex                    # Trebejo.Docker, SafeCommand, Apero.Proc
lib/delfos/cli/commands/setup/llm.ex                   # Alaja.Wizard
lib/delfos/cli/commands/setup/llm/external.ex          # remove embedding prompts
lib/delfos/cli/commands/setup/llm/llama_cpp.ex         # reduce 10 → 3 prompts
lib/delfos/cli/commands/setup/llm/ollama.ex            # remove detect_ollama_dim
lib/delfos/llm/client.ex                               # Apero.Retry → Arrea.CircuitBreaker
lib/delfos/config/llm_discovery.ex                     # ensure_embedding_server/0, Apero.Proc
lib/delfos/config/postgres_discovery.ex                # Apero.Proc
lib/delfos/config/manager.ex                           # eliminar migrate_from_toml si v2.x no necesita

test/delfos/cli/commands/agents_test.exs               # remove --symbol tests
test/delfos/cli/commands/audit_test.exs                # add --with-explanation, --llm-less
test/delfos/cli/commands/config_test.exs               # remove wizard/doctor/probe tests
test/delfos/cli/commands/doctor_test.exs               # --guided
test/delfos/cli/commands/explain_test.exs              # --llm-less, --no-cache
test/delfos/cli/commands/init_test.exs                 # --force, --with-summary, --with-briefing
test/delfos/cli/commands/integrate_test.exs            # vscode
test/delfos/cli/commands/integrate_formats_test.exs    # vscode schema validation
test/delfos/cli/commands/query_test.exs                # --llm-less
test/delfos/cli/commands/scan_test.exs                 # AnimatedBar output
test/delfos/cli/commands/status_test.exs               # --statistics
test/delfos/cli/commands/summarize_test.exs           # Arrea.run_sync
test/delfos/cli/cli_test.exs                           # deprecation aliases

config/config.exs                                       # actualizar source_ref a v2.3.0 cuando tag
mix.exs                                                 # @version 2.2.1 → 2.3.0

docs/SPEC.md                                            # resync
docs/HANDOFF.md                                         # limpiar cuentas
docs/REMAINING_TASKS.md                                 # §3.1 fix, §16-19 con plan
docs/SESSION_STATE.md                                   # actualizar a v2.3.0
docs/MCP_TOOLS.md                                       # serve → mcp
docs/LLM_USAGE.md                                       # tabla actualizada
docs/TEST_PLAN.md                                       # cerrar T16-T22
audit_delfos.txt                                        # corregir Botica mentira
README.md                                               # tabla comandos
README.es.md                                            # tabla comandos
CHANGELOG.md                                            # [2.3.0] entry
```

### 16.2 Archivos a CREAR

```
lib/delfos/audit/narrative.ex                           # LLM-powered diagnosis
lib/delfos/cli/help.ex                                  # Alaja-based uniform help renderer
test/delfos/audit/narrative_test.exs                    # unit tests
```

### 16.3 Archivos a ELIMINAR

```
lib/delfos/cli/commands/stadistics.ex                   # typo
test/delfos/cli/commands/stadistics_test.exs            # typo
test/delfos/statistics_test.exs                         # el módulo Statistics se mantiene, los tests se mueven a status_test.exs
test/delfos/statistics_integration_test.exs             # idem
test/delfos/cli/commands/context_test.exs (si existe)  # context eliminado
```

---

## 17. Apéndice B — Matriz embeddings / LLM final

### 17.1 Comandos que SIEMPRE usan embeddings

- `scan` (vía FileProcessor)
- `query` (vía HybridSearch)
- `explain` (vía find_symbol + related chunks)

### 17.2 Comandos que SIEMPRE usan LLM

- `explain` (chat completion para resumen)
- `summarize` (chat completion para resúmenes)
- `mcp` server (vía tools)

### 17.3 Comandos que OPCIONALMENTE usan embeddings/LLM (con `--llm-less`)

- `query --llm-less`: solo BM25 + graph (sin vector)
- `explain --llm-less`: solo static info (sin chat LLM)
- `audit --with-explanation`: añade LLM diagnosis
- `agents --with-explanation`: añade LLM executive summary
- `graph cycles --llm-explain`: LLM explica cada SCC
- `init --with-summary`: encadena summarize
- `init --with-briefing`: encadena agents

### 17.4 Comandos que NUNCA usan modelos

- `audit` (sin `--with-explanation`)
- `agents` (sin `--with-explanation`)
- `graph` (sin `--llm-explain`)
- `status`
- `doctor`
- `config`
- `integrate`
- `version`

---

## 18. Apéndice C — Lista final de comandos

### Top-level (14)

```
delfos init [path] [--force] [--with-summary] [--with-briefing] [--llm-less]
delfos scan [--full] [--workers N] [--llm-less]
delfos query <text> [--kind K] [--level L] [-n N] [--format text|json] [--llm-less]
delfos explain <name> [--fresh] [--no-cache] [--llm-less]
delfos audit [--file path] [--with-explanation] [--llm-less]
delfos summarize [--level N] [--force]
delfos graph <callers|callees|impact|cycles> <name> [--depth N] [--llm-explain]
delfos agents [--output dir] [--with-explanation]
delfos status [--statistics]
delfos doctor [--fix] [--guided] [--json]
delfos config <subcommand>           # ver §6.2
delfos integrate <agent|all> [--yes] [--project path]
delfos mcp
delfos version
```

### Sub-comandos config (8)

```
delfos config show
delfos config path
delfos config init
delfos config get <section> <key>
delfos config set <section> <key> <value>
delfos config preset <name>
delfos config setup [db|llm]
delfos config models
```

### Sub-comandos integrate (1 principal + N agents)

```
delfos integrate all
delfos integrate <agent>
```

Donde `<agent>` ∈ {claude-code, opencode, cursor, aider, codex, zed, vscode, [windsurf, continue, claude-desktop, roo-code]}

### Aliases (mantener 1 versión, eliminar en v3.0)

```
delfos watch     → delfos mcp
delfos serve     → delfos mcp
delfos context   → delfos agents
```

---

## 19. Apéndice D — Notas finales

### 19.1 Política de git dates

Recordatorio del HANDOFF.md §2: commits entre **20:00-02:00 Berlin** en días laborables.

### 19.2 Conventional commits

`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:` — todos en inglés.

### 19.3 Bump de versión

Pasar de `2.2.1` → `2.3.0` (minor, no breaking).
**Breaking**: los aliases deprecados en v2.3.x se eliminan en v3.0.0.

### 19.4 Source ref en mix.exs

`source_ref: "1.0.0"` está congelado. Actualizar a `"v#{@version}"` o al tag actual.

### 19.5 CVEs de req

Pendiente §7.5 de NEXT_PHASE.md: bumpear `req ~> 0.5` a `~> 0.5.19`. No es parte de este plan estrictamente, pero se debe hacer.

---

## 20. Metadata del documento

| Campo | Valor |
|---|---|
| Generado | 2026-07-15 |
| Versión del plan | 1.0 |
| Estado | Pendiente de aprobación |
| Próxima sesión | Ejecutar Fase A (Quick Wins) |
| Duración estimada total | 5-7 sesiones de coder + 1 de documentador |
| Decisor final | Usuario (Lorenzo-SF) |
| Aprobado | ❌ |

---

## 21. Preguntas para el usuario antes de empezar

1. **¿Aprobamos el plan tal cual, o ajustamos fases?**
2. **¿Qué fase arrancamos primero — A (Quick Wins) o D (Integraciones)?**
3. **¿Mantenemos los 3 aliases deprecados (`watch`, `serve`, `context`) o los eliminamos inmediatamente?**
4. **¿Cuántas integraciones añadimos — solo `vscode` o también `windsurf`/`continue`/`claude-desktop`/`roo-code`?**
5. **¿El typo `stadistics` se renombra a `statistics` o se mantiene por consistencia con algún workflow existente?**
6. **¿Quién ejecuta el plan — coder, documentador, o mixto?**
7. **¿Esta fase requiere actualizar la `REMAINING_TASKS.md` con estos items como §16-19?**

---

**FIN DEL DOCUMENTO**

Una vez aprobado, ejecutar con `model-orchestrator`. La Fase A es la de menor riesgo y máxima visibilidad — recomendada para arrancar.