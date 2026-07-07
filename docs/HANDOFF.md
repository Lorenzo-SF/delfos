# Lorenzo-SF OSS Handoff — Project Context Document

> **Purpose**: Resume el estado actual de los 9 repos del usuario (7 OSS + 2 privados)
> para que cualquier sesión nueva de opencode/claude code pueda retomar el trabajo sin
> tener que re-explorar. Pensado para ser leído al inicio de una nueva conversación.
>
> **Audience**: un agente que conoce Elixir pero no ha visto este código. El documento
> da estado real, decisiones tomadas, y lo que falta — no marketing ni planes.

---

## 1. Identidad y motivación

El usuario es **Lorenzo-SF**. Maneja 9 proyectos Elixir que viven como ecosistema:

- 5 OSS activos: `pote, alaja, arrea, candil, botica` (públicos en github.com/Lorenzo-SF)
  - Apero ya **no** es dep runtime de Delfos (crypto AES-256-GCM migrada a `:crypto` de Erlang inline; resto absorbido por Botica/Candil).
- 2 privados: `delfos, flotilla, valvula` (también bajo Lorenzo-SF, no OSS)
  - (Nota: 9 = 7 OSS + 3 privados; el documento lista 9)

**Motivación**: los repos tienen que estar "**dignos de meter en un CV**". Es decir:

- README, tests, docs, CI, ejemplos
- API coherente entre los 7 proyectos
- Releases bien etiquetados (SemVer)
- Repos limpios (sin TODOs visibles, sin código muerto, sin warnings de credo/dialyzer)

El usuario habla **español** en conversación pero **inglés** en todos los archivos del repo
(README, docs, CHANGELOG, código, mensajes de commit). **Sigue esta regla sin excepciones.**

---

## 2. Política inquebrantable: fechas de git

El usuario es un profesional que quiere que su GitHub parezca que programa **fuera de
horario de oficina** (no quiere que un reclutador vea que clava código de 9 a 18).

**Reglas**:

1. **Ventana de 6h**: todos los commits que yo (Mavis) haga o pushee van entre
   **20:00 y 02:00 Europe/Berlin** en días laborables (lun-vie).
2. **Finde (sáb-dom)**: la hora da igual.
3. **Vacaciones 2026-06-18 → 2026-06-28**: los commits de esos días también se mueven
   a la ventana 20-02 con `filter-branch` (ver script `/tmp/rewrite_dates3.py`).
4. **Tags**: cuando un commit cambia de SHA, el tag se borra (`git tag -d X`) y se
   re-crea (`git tag -a X new_sha`) — los tags annotated ya tienen un tag object propio.

**Implementación**:

```bash
export GIT_AUTHOR_DATE="2026-06-29T22:00:00+02:00"  # ejemplo: 22:00 Berlin
export GIT_COMMITTER_DATE="2026-06-29T22:00:00+02:00"
git commit -m "..."
```

Para reescribir históricos hay un script Python en `/tmp/rewrite_dates3.py`. Si lo necesitas
de nuevo en una sesión limpia, está descrito abajo en §13.

**Fecha actual**: 2026-06-29 (lunes), 16:26 Berlin. Cualquier commit que hagas tiene que
forzar la fecha a la ventana, ej. `20:00+02:00` o `21:30+02:00`. Un commit a las 16:30
Berlin es una metedura de pata operacional.

---

## 3. Los 9 repos: ecosistema y dependencias

```
                  ┌──────┐
                  │ pote │ ◄─── (no tiene deps internas; lib base de themes)
                  └──────┘
                     ▲
                     │ use Pote.Theme
                  ┌──────┐
                  │ alaja│ ◄─── todo lo usa: rendering + themes + CLI DSL
                  └──────┘
                     ▲
                     │ dependencia
   ┌─────────────────┴─────────────────┐
   │                                   │
┌──────┐                         ┌──────┐
│arrea │                         │botica│
└──────┘                         └──────┘
   ▲                                 ▲
   │                                 │
   │           ┌──────┐              │
   └───────────┤candil├──────────────┘
               └──────┘
                  ▲
                  │
               (consumido por)
                  │
              ┌─────────┐
              │ flotilla│  (privado; Phoenix LiveView renderer que USa alaja)
              └─────────┘
                  ▲
                  │
              ┌─────────┐
              │ valvula │  (privado; rate limiting; defensivo "NOT a Plug")
              └─────────┘
                  ▲
                  │
              ┌─────────┐
              │  delfos │  (privado; CLI SELF-HOSTING que USA: pote+alaja+arrea+botica+candil; crypto inline sobre `:crypto` de Erlang)
              └─────────┘
```

**Regla fundamental**: las libs OSS se pinean a `branch: "main"` (NO tags), porque
historicamente:

- pin a `tag: "v0.2.0"` rompió pote (no tenía `Pote.Theme`)
- pin a `tag: "v0.2.0"` rompió candil (no tenía `Provider`)
- pin a `tag: "v0.3.8"` rompió alaja (tenía `question_with_options/3` roto)

→ En delfos `mix.exs`:

```elixir
{:alaja,  github: "Lorenzo-SF/alaja",  branch: "main"},
{:arrea,  github: "Lorenzo-SF/arrea",  branch: "main"},
{:botica, github: "Lorenzo-SF/botica", branch: "main"},
{:candil, github: "Lorenzo-SF/candil", branch: "main"},
# Nota (2026-07): {:apero, ...} ya NO está — su crypto vive inline en
# Delfos.Config.Manager sobre `:crypto` de Erlang. Ver §7.3.
```

NO uses `tag:` ni `path:` en las dependencias del ecosistema.

---

## 4. Estado por proyecto

### 4.1 `pote` (OSS) — v0.3.1 (tag), main `2fe9d8d`

**Qué es**: lib base de configuración + sistema de temas "heredable". Pequeño.

**API pública clave**:
- `use Pote.Theme, config_app: :alaja, defaults: %{...}` — macro que genera facade
  (list/0, active/0, activate/1, color/1, colors/0, install!/1, install_template/1,
  templates/0, register_with_pote/0, ensure_registered/0)
- Stack de "resolvers" — varios consumers pueden ser registrados y el lookup es por
  prioridad
- El host **DEBE** definir `storage_dir/0`; el macro no lo genera

**Estado**: terminado funcionalmente.

**Tests**: pasan. Limpiado y auditado.

**Lo que falta**: nada urgente. Si quieres, puedes añadir tests para el caso edge
"multiple themes registered at once".

### 4.2 `alaja` (OSS) — v0.3.12 (tag), main `c2599df` (= `18ed56d`)

**Qué es**: la **lib central**. Render TUI + DSL para componentes + CLI + theme resolver.
~63 archivos `.ex`, ~10k LOC.

**Capacidades**:
- `Alaja.print_raw/1`, `Alaja.print_info/1`, `Alaja.print_warning/1`, `Alaja.print_error/1`,
  `Alaja.print_success/1`
- **Cell/Buffer engine** (la representación interna de cada bloque de texto)
- **Box transversal** (post-processor; concepto como `<div>` en HTML — envuelve el output)
- DSL: `use Alaja.CLI.Definition, otp_app: :my_app` que genera `main/1`
  - `Alaja.CLI.Definition.dispatch_main/1` arranca `:alaja` y la OTP app del host
    (esto es **crítico** para que funcione en releases)
- **Alaja.Theme** — facade sobre `Pote.Theme`
- **Alaja.Printer.Interactive.question_with_options/3** — robusto a partir de v0.3.12:
  acepta índice 1-based, etiqueta exacta, prefijo (case-insensitive), nombre atom
  (`llm`), o `:error`. Tiene `:default` kwarg.
- **Syntax engine** — `Alaja.Syntax.register_language/2`, `Alaja.Syntax.highlight_content/2`
  (engine + language + renderer + special + theme)
- 67 archivos de lenguajes en delfos que se registran contra Alaja.Syntax

**Estado**: terminado. Hay un bug menor histórico: el **box transversal** se aplicaba a
`print_raw/2` con `Buffer.t() + :box` y crasheaba con `ArgumentError: not an iodata term`;
esto se arregló en v0.3.4 y `v0.3.12`.

**Lo que falta**:
- v0.3.13 candidate: el flag `--colors` en `alaja color --colors` lista los colores del
  theme activo (puede que ya esté en main).

### 4.3 `arrea` (OSS) — v0.3.7 (tag), main `5546492` (= `1a29aef`)

**Qué es**: wrapper Elixir sobre el patrón [Arrea](https://hex.pm/packages/arrea)
— backpressure, JSON encoding safe, telemetry wired. ~30 archivos.

**Estado**: terminado. 191 tests pasan (1 pre-existing failure documentado).

### 4.4 `apero` (OSS) — v0.2.2 (tag), main `93e3f72` (= `93f2909`)

> **Nota (2026-07):** ya **no** es dependencia runtime de Delfos. Se
> mantiene el repo OSS para otros consumidores, pero las piezas que
> Delfos necesitaba (crypto AES-256-GCM, random) se migraron inline.

**Qué era**: utilidades varias (crypto AES-256-GCM, random, SSH key
verification). ~28 archivos.

**Estado del repo OSS**: terminado. SSH key verification, unbiased
random password. Última versión consumida por Delfos: v0.2.2 / main
`93f2909`. Ningún consumidor activo dentro de Delfos tras la migración.

### 4.5 `botica` (OSS) — v0.2.0 (tag), main `fe519f0` (= `4ec3254`)

**Qué es**: features flags ETS + health checks + concurrency cap.
~16 archivos.

**Estado**: terminado. Tiene `Botica.Doctor` (motor de checks), `Botica.Flags` (ETS).

### 4.6 `candil` (OSS) — v0.3.1 (tag), main `c876866` (= `5615bdf`)

**Qué es**: cliente LLM con `Candil.Provider` struct (v0.3.0+), circuit breaker,
retry, rate limiting, context validation, checksums. ~18 archivos.

**Estado**: terminado.

**API breaking v0.2.x → v0.3.0**: `Candil.Provider` es ahora un struct (antes era un map).
Los consumers (delfos) usan `Candil.Provider` para configurar el provider.

### 4.7 `delfos` (PRIVADO) — v0.4.18 (tag), main `f017d1a`

**Este es el proyecto principal y el que más trabajo consume.**

**Qué es**: code-search + indexador CLI, self-bootstrapping, con:
- Indexing incremental de proyectos (watcher)
- Búsqueda semántica (embeddings via pgvector + HNSW)
- Sintaxis highlighting (via Alaja.Syntax)
- Tree-sitter para parsers AST (27 lenguajes)
- Batamanta → release binario standalone

**Estructura**:
```
lib/delfos/
├── application.ex                   # arranca Supervisor + migraciones
├── cli.ex                           # DSL Alaja.CLI.Definition
├── cli/commands/                    # 16 subcommands
│   ├── doctor.ex                    # botica-based diagnostic
│   ├── setup.ex + setup/{db,llm}.ex # wizards interactivos
│   ├── query.ex / audit.ex / explain.ex / summarize.ex
│   ├── scan.ex / graph.ex / context.ex
│   ├── models.ex / config.ex / integrate.ex / status.ex
│   ├── watch.ex / serve.ex / gen.ex (a.k.a. release.build)
│   └── init.ex
├── parsers/
│   ├── dispatcher.ex                # ext → lang
│   ├── treesitter/tree_sitter.ex    # NIF binding
│   ├── treesitter/tree_sitter_nif   # no directo - va via NIF
│   ├── generic_parser.ex            # regex fallback
│   ├── dart_parser.ex / hcl_parser.ex / yaml_parser.ex / python_parser.ex / typescript_parser.ex / elixir_parser.ex
├── llm/candil_bridge.ex             # provider wiring
├── mcp/server.ex                    # MCP stdio server (async stdin reader)
├── syntax/registry.ex               # registra los 67 idiomas en Alaja
├── syntax/<67 langs>.ex             # cada uno con `definition/0` returning %Alaja.Syntax.Language{}
├── health.ex                        # periodic health check
├── repo_starter.ex                  # wrapper que inicia Repo on-demand
├── config/manager.ex                # JSON config + AES-256-GCM
└── indexer/                         # pipeline de ingestión
```

**Tests**: 16 archivos de tests, ~100 tests. Cobertura razonable pero mejorable.

**Lo que está hecho**:
- [x] CLI migrado a `Alaja.CLI.Definition`
- [x] Doctor estructurado por secciones (Postgres / TreeSitter / Models / Config)
- [x] `Application.start/2` corre migraciones automáticamente
- [x] `delfos setup [db|llm]` acepta args para saltar al sub-wizard
- [x] Docker conflict resuelto (asks user en vez de fallar)
- [x] Batmanta genera binario en raíz del proyecto (donde está mix.exs)
- [x] `gen: ["batamanta", "deploy"]` — alias canónico
- [x] 27 lenguajes en tree-sitter NIF
- [x] 67 archivos de syntax highlighting registrados en Alaja
- [x] JSON config cifrado con AES-256-GCM (inline sobre `:crypto` de Erlang — antes vía Apero)
- [x] MCP server async stdin
- [x] pgvector + HNSW indexes

**Lo que falta / está en progreso**:

1. **Arreglar el conflicto de tree-sitter-perl** — RESUELTO en v0.4.18 quitándolo.
   Pero el usuario quiere ahora **añadir los lenguajes que faltan** al tree-sitter NIF:
   - `kotlin` — tree-sitter 0.25 no lo soporta upstream; considerar `tree-sitter-kotlin-ng` (fork comunidad)
   - `r` — sí existe `tree-sitter-r`, debería funcionar con tree-sitter 0.25
   - `powershell` — sí existe `tree-sitter-powershell`
   - `assembly` — sí existe `tree-sitter-asm`
   - `groovy` — sí existe `tree-sitter-groovy`
   - `fsharp` — sí existe `tree-sitter-fsharp` (community)
   - `vb` — `tree-sitter-vbnet` (community)
   - `objective-c` — sí, `tree-sitter-c` lo cubre parcialmente; mejor `tree-sitter-objc`

2. **Tests**: 12 de 15 CLI commands no tienen tests dedicados:
   - `init`, `scan`, `query`, `audit`, `summarize`, `explain`, `graph`, `context`, `status`, `setup`, `gen`, `watch`, `serve`
   - `doctor`, `models`, `integrate`, `config` sí tienen tests.

3. **Highlight output**: aunque tenemos los 67 archivos de syntax, muchos comandos (`explain`, `audit`, `query`) no invoca el highlight. Wire-up pendiente.

4. **TUI framework**: el usuario quiere un proyecto aparte (sugerido: `Tulja`, `Tende`, o `Lex`)
   que USe alaja como visual layer. **NO en alaja** — alaja se queda puro. Esto es posterior
   a delfos estable.

---

## 5. Delfos comandos CLI: estado por subcommand

Comandos de `delfos <subcommand>` registrados vía `use Alaja.CLI.Definition, otp_app: :delfos`:

| Subcommand | Tests | Notas |
|------------|-------|-------|
| `init` | ❌ | Inicializa `~/.config/delfos/` |
| `scan` | ❌ | Indexa proyecto |
| `query` | ❌ | Búsqueda semántica |
| `audit` | ❌ | Auditoría |
| `summarize` | ❌ | Resumen con LLM |
| `explain` | ❌ | Explica código (highlight código con Alaja.Syntax) |
| `graph` | ❌ | Genera grafo de relaciones |
| `context` | ❌ | Genera contexto para LLM |
| `doctor` | ✅ | Estructurado en 4 secciones |
| `status` | ❌ | Estado actual |
| `config` | ✅ | JSON show / path / preset / init / set / get |
| `integrate` | ✅ | Codex (TOML), Cursor (MDC), Aider (regex merge) — `safe_write/2` |
| `models` | ✅ | `--probe` para LLM providers |
| `setup` | ✅ (parcial) | Wizard raíz o `setup [db\|llm]` |
| `watch` | ❌ | Watcher |
| `serve --mcp` | ❌ | MCP stdio server |
| `gen` (alias batamanta/deploy) | N/A | Construye binario |

---

## 6. Delfos convenciones internas

### 6.1 Nombres de archivo
- `lib/delfos/<feature>.ex` para el módulo principal
- `lib/delfos/<feature>/<subfeature>.ex` para submódulos
- `test/delfos/<feature>_test.exs` o `test/delfos/<feature>/<subfeature>_test.exs`

### 6.2 Aliases
- `mix gen` → `["batamanta", "deploy"]` (construye + instala en `~/bin/delfos`)
- `mix deploy` → copia `./delfos` → `~/bin/delfos`
- `mix quality` → `format + compile --warnings-as-errors + test + credo --strict --format=oneline + run bench + coveralls + dialyzer`
- `mix lint` → `format --check-formatted + credo --strict`

### 6.3 Credo & Dialyzer
- Credo **strict** está activo. Reglas que violan más:
  - `Credo.Check.Refactor.NestedModule`
  - `Credo.Check.Refactor.Apply` sobre `Enum.map_join`
  - `Credo.Check.Refactor.CondStatements` (preferir `if` sobre `cond` para 2 ramas)
  - `Credo.Check.Warning.UnusedVariable` (prefijo `_` para silenciar)
- Dialyzer **strict** también. Errores frecuentes:
  - `pattern_match_cov` (else inalcanzable)
  - `no_return`
  - `ets.select_delete` con closure
  - `apply/2` dinámico

### 6.4 Configuración prod
- `config/prod.exs` usa `database: "delfos_dev"` (NO `delfos_prod`)
- `config/runtime.exs` valida env en runtime
- `MIX_ENV=prod mix gen` produce el binario que instala con su propio DB

### 6.5 Alaja.CLI.Definition
```elixir
use Alaja.CLI.Definition, otp_app: :delfos
```
Internamente este DSL genera un `main/1` que llama a `dispatch_main/1`, que ahora
(en alaja v0.3.12) hace:
1. `Application.ensure_all_started(:alaja)`
2. `Application.ensure_all_started(__otp_app__())`  # crítico para releases
3. Despacha args al subcommand apropiado

Si una lib no usa `Alaja.CLI.Definition`, no se beneficia de esto. Pero todas las del
ecosistema lo hacen.

---

## 7. Delfos: decisiones clave del diseño

### 7.1 Self-bootstrapping
`mix gen` (que es `mix batamanta && mix deploy`) es el ÚNICO comando que el usuario
debe conocer después de `git clone`. Una vez ejecutado:
- Batmanta genera binario en raíz del proyecto (donde está mix.exs)
- `mix deploy` lo copia a `~/bin/delfos`
- Usuario añade `~/bin` a PATH
- Puede ejecutar `delfos` desde cualquier lado

### 7.2 `Application.start/2` con auto-migración
Antes de cualquier otra cosa (incluso antes de procesar args del CLI), arranca:
- `Delfos.RepoStarter` (no inicia el Repo real, solo el GenServer wrapper)
- Supervisor arranca
- `maybe_run_migrations()` corre async en un Task

Esto significa que las migraciones se aplican en la primera invocación de cualquier
subcommand, no necesitas un paso "init" separado.

### 7.3 Config cifrada
`~/.config/delfos/delfos.conf` es JSON cifrado con AES-256-GCM **inline**
sobre `:crypto` de Erlang (Delfos.Config.Manager). Antes se delegaba en
`Apero.Crypto.Cipher`; desde 2026-07 Apero ya no es dep runtime, y la
implementación AES-GCM vive directamente en el proyecto. Master key de
una env var `DELFOS_MASTER_KEY` o generada on first run.

### 7.4 Doctor estructurado
`delfos doctor` agrupa checks en 4 secciones:

```
[Postgres]
  ✓  db: created
  ✓  pgvector: enabled (v0.7.4)
  ✓  migrations: applied

[TreeSitter]
  ✓  NIF: available

[Models]
  ✓  configured: yes
  ✓  embeddings: yes
  ✓  llm (chat): yes

[Config]
  ✓  file: /home/user/.config/delfos/delfos.conf
```

Si algo falla, sugiere el wizard apropiado (`delfos setup db` / `delfos setup llm`)
en `maybe_suggest_setup/2`.

### 7.5 Dispatcher
`lib/delfos/parsers/dispatcher.ex` resuelve extensión → lenguaje, luego:

```elixir
def parse(path, content) do
  ext = Path.extname(path) |> String.downcase()
  lang = Map.get(@language_map, ext, "unknown")
  cond do
    ext in [".dart"] -> {:ok, DartParser.parse(path, content)}
    ext in [".tf", ".hcl"] -> {:ok, HCLParser.parse(path, content)}
    ext in [".yaml", ".yml"] -> {:ok, YAMLParser.parse(path, content)}
    TreeSitter.supported?(lang) -> TreeSitter.parse(path, content, lang)
    true -> {:ok, GenericParser.parse(path, content)}
  end
end
```

### 7.6 Tree-sitter NIF (27 lenguajes)
`native/tree_sitter_nif/` tiene:
- `Cargo.toml` con 27 grammars
- `src/lib.rs` que carga el NIF
- `.cargo/config.toml` para `dynamic_lookup` rustflag (macOS)
- `tree_sitter.ex` (en `lib/delfos/parsers/treesitter/`) que:
  - `@supported_languages ~w(...)` lista
  - `parse/3` dispatche al NIF o GenericParser
  - `normalize_lang/1` convierte aliases (ej "erlang" → dispatch a uno real)

**Lenguajes fuera del NIF** (caen al regex `GenericParser`):
- `perl` (quitado en v0.4.18 por conflicto de versiones)
- `kotlin` (tree-sitter 0.25 no lo soporta upstream)
- `r`, `powershell`, `assembly`, `groovy`, `fsharp`, `vb`, `objective-c` (no añadidos)

**Pendiente del usuario**: añadir los que se pueda. Candidato seguros (con tree-sitter
0.25 compatible):
- `tree-sitter-r = "*"`
- `tree-sitter-powershell = "*"`
- `tree-sitter-asm = "*"`
- `tree-sitter-groovy = "*"` (verificar version de tree-sitter)
- Para `kotlin`: usar `tree-sitter-kotlin-ng` u otro fork
- Para `fsharp`, `vb`, `objective-c`: forks comunitarios

---

## 8. Pipeline de commit

Cuando Mavis hace un commit:

```bash
# Política obligatoria: fecha en ventana 20-02:00 Berlin
# Hoy (2026-06-29 16:26 Berlin), la ventana termina a las 02:00 de mañana
# Si ya pasaron las 02:00, usamos la ventana de esta noche (20:00 Berlin)
export GIT_AUTHOR_DATE="2026-06-29T22:00:00+02:00"
export GIT_COMMITTER_DATE="2026-06-29T22:00:00+02:00"

git add -A
git commit -m "..."
```

Cuando se bumpea versión:

1. `sed -i 's/@version "X.Y.Z"/@version "X.Y.Z+1"/' mix.exs`
2. Añadir entrada en CHANGELOG.md
3. Commit con mensaje que sigue convención `fix(delfos): descripcion` o `feat(...)` o `chore(...)`
4. `git tag -d vX.Y.Z` (borra viejo)
5. `git tag -a vX.Y.Z+1 -m "vX.Y.Z+1 — descripcion corta"`
6. `git push origin main --force` (en delfos hay SHAs que se mueven por reescritura)
7. `git push origin --tags --force`

En `mix.exs`, el campo `source_ref` usa `"v#{@version}"` para que ExDoc genere links correctos.

---

## 9. Tests

Para ejecutar tests sin una DB (modo sandbox):

```bash
elixir --erl "+fnu" -pa _build/dev/lib/*/ebin -r ExUnit -e "
ExUnit.start(autorun: false)
Code.require_file(\"test/delfos/<feature>_test.exs\")
ExUnit.run()
"
```

**Problemas comunes**:

- `actions.cache@v4` GitHub Actions devuelve 422 → usar `actions/cache@v4` igual
- `--warnings-as-errors` está desactivado en delfos CI (creaba falsos warnings)
- `mix release` con `MIX_ENV=prod` + `Application.spec/2` → spec nil → fallback
  a "0.0.0+unknown" en runtime

---

## 10. Sandbox notes (recordatorio para el agente)

- **Elixir se reinstala por sesión**: `/tmp/elixir-1.18/bin/` se borra. Si necesitas Elixir,
  descárgalo: `wget https://github.com/elixir-lang/elixir/releases/download/v1.18.4/elixir-otp-25.zip`
- **Cargo 1.65 en sandbox NO compila tree-sitter** — Cargo es de Debian, demasiado viejo.
  Los tests de la NIF no se pueden ejecutar en sandbox. La máquina del usuario sí tiene
  Rust 1.78+ y compila bien.
- **OTP 25 desde apt** con `apt install erlang` (puede requerir `apt update` primero
  en sandbox nuevo).

---

## 11. Lenguajes del ecosistema: protocolo "digno de CV"

Cada repo OSS debe tener:
- [x] README en inglés + docs/README.es.md
- [x] CHANGELOG.md con Keep-a-Changelog format
- [x] mix.exs con `docs: [main, extras, source_url, source_ref]`
- [x] CI con matrix Elixir + OTP
- [x] Tests pasando
- [x] Sin credo strict warnings
- [x] Sin dialyzer strict warnings
- [x] Versión con tag SemVer
- [x] Lockfile consistente

---

## 12. Tabla de tags actual (esperado)

| Repo | Tag | Estado |
|------|-----|--------|
| pote | v0.3.1 | ✅ |
| alaja | v0.3.12 | ✅ |
| arrea | v0.3.7 | ✅ |
| botica | v0.2.0 | ✅ |
| candil | v0.3.1 | ✅ |
| apero | v0.2.2 | ⛔ (no es dep runtime de Delfos desde 2026-07) |
| flotilla | v0.2.0 | ✅ |
| valvula | v0.2.0 | ✅ |
| delfos | **v0.4.18** | ✅ (recién pusheado) |

Si te encuentras un repo con tag desactualizado, bumpear siguiendo el patrón del §8.

---

## 13. Script de reescritura de fechas (recrear si la sesión es nueva)

`/tmp/rewrite_dates3.py` reescribe commits con la política 20-02:00. Si lo necesitas
y no está (sesión nueva), aquí está:

```python
#!/usr/bin/env python3
import subprocess, datetime, zoneinfo, sys, os, re

REPO = sys.argv[1]
SINCE = sys.argv[2] if len(sys.argv) > 2 else "2026-06-29"
TZ = zoneinfo.ZoneInfo("Europe/Berlin")

def is_weekend(d): return d.weekday() in (5, 6)
def in_window(ld): return ld.hour >= 20 or ld.hour < 2
def project(ld):
    if is_weekend(ld.date()): return ld
    if in_window(ld): return ld
    return ld.replace(hour=22, minute=ld.minute, second=ld.second)

out = subprocess.check_output([
    "git","-C",REPO,"log","--reverse",
    f"--since={SINCE} 00:00 +0000",
    "--pretty=format:%H|%at|%ct|%an|%ae"
], text=True).splitlines()

commits = []
for line in out:
    parts = line.split("|",4)
    if len(parts) != 5: continue
    sha, a_ts, c_ts, an, ae = parts
    if not all(c in "0123456789abcdef" for c in sha): continue
    commits.append((sha, int(a_ts), int(c_ts), an, ae))

if not commits:
    sys.exit(0)

new_auths, new_comms = [], []
for sha, a_ts, c_ts, an, ae in commits:
    la = datetime.datetime.fromtimestamp(a_ts, tz=datetime.timezone.utc).astimezone(TZ)
    lc = datetime.datetime.fromtimestamp(c_ts, tz=datetime.timezone.utc).astimezone(TZ)
    new_auths.append(int(project(la).timestamp()))
    new_comms.append(int(project(lc).timestamp()))

def mono(seq):
    fixed=[]; last=0
    for v in seq:
        if v<=last: v=last+1
        fixed.append(v); last=v
    return fixed
new_auths = mono(new_auths); new_comms = mono(new_comms)

def commit_parents(sha):
    raw = subprocess.check_output(["git","-C",REPO,"cat-file","-p",sha], text=True)
    return [l.split(" ",1)[1] for l in raw.splitlines() if l.startswith("parent ")]

def commit_msg(sha):
    raw = subprocess.check_output(["git","-C",REPO,"cat-file","-p",sha], text=True)
    if "\n\n" in raw:
        _, _, msg = raw.partition("\n\n")
    else: msg = ""
    return msg

def commit_tree(sha):
    raw = subprocess.check_output(["git","-C",REPO,"cat-file","-p",sha], text=True)
    for line in raw.splitlines():
        if line.startswith("tree "):
            return line.split(" ",1)[1]
    raise RuntimeError(f"no tree for {sha}")

parent_map = {}
rewritten = []
for i, (sha, a_ts, c_ts, an, ae) in enumerate(commits):
    la = datetime.datetime.fromtimestamp(a_ts, tz=datetime.timezone.utc).astimezone(TZ)
    if is_weekend(la.date()) or in_window(la):
        if (new_auths[i], new_comms[i]) == (a_ts, c_ts):
            continue

    ps = commit_parents(sha)
    if len(ps) != 1: continue  # skip merges

    tree = commit_tree(sha)
    msg = commit_msg(sha)
    new_parents = [parent_map.get(p, p) for p in ps]

    a_dt = datetime.datetime.fromtimestamp(new_auths[i], tz=TZ).astimezone(datetime.timezone.utc)
    c_dt = datetime.datetime.fromtimestamp(new_comms[i], tz=TZ).astimezone(datetime.timezone.utc)
    env = os.environ.copy()
    env["GIT_AUTHOR_NAME"]    = "Lorenzo-SF"
    env["GIT_AUTHOR_EMAIL"]   = "Lorenzo-SF@users.noreply.github.com"
    env["GIT_COMMITTER_NAME"] = "Lorenzo-SF"
    env["GIT_COMMITTER_EMAIL"]= "Lorenzo-SF@users.noreply.github.com"
    env["GIT_AUTHOR_DATE"]    = a_dt.strftime("%Y-%m-%dT%H:%M:%S+00:00")
    env["GIT_COMMITTER_DATE"] = c_dt.strftime("%Y-%m-%dT%H:%M:%S+00:00")

    args = ["git","-C",REPO,"commit-tree",tree,"-F","-"] + [f"-p{p}" for p in new_parents]
    proc = subprocess.run(args, env=env, input=msg, text=True, stdout=subprocess.PIPE, check=True)
    parent_map[sha] = proc.stdout.strip()
    rewritten.append(sha)
    print(f"  {sha[:8]} → {parent_map[sha][:8]} (was {la.isoformat()}, will be {a_dt.isoformat()})", file=sys.stderr)

# Update main branch / HEAD
head = subprocess.check_output(["git","-C",REPO,"rev-parse","HEAD"], text=True).strip()
if head in parent_map:
    new_head = parent_map[head]
    try:
        head_target = subprocess.check_output(
            ["git","-C",REPO,"symbolic-ref","HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        head_target = None
    if head_target:
        subprocess.run(["git","-C",REPO,"update-ref",head_target,new_head], check=True)
    else:
        try:
            subprocess.run(["git","-C",REPO,"update-ref","refs/heads/main",new_head], check=True)
        except Exception: pass
        subprocess.run(["git","-C",REPO,"update-ref","HEAD",new_head], check=True)

# Re-tag annotated tags pointing to rewritten commits
for sha in rewritten:
    new_sha = parent_map[sha]
    refs_out = subprocess.check_output([
        "git","-C",REPO,"for-each-ref","refs/tags/",
        "--format=%(refname) %(objectname) %(objecttype)"
    ], text=True)
    for line in refs_out.splitlines():
        if not line.strip(): continue
        parts = line.split(" ", 2)
        if len(parts) < 3: continue
        refname, sha_target, obj_type = parts[0], parts[1], parts[2]
        try:
            sha_commit_target = subprocess.check_output(
                ["git","-C",REPO,"rev-parse", sha_target + "^{commit}"], text=True).strip()
        except Exception: continue
        if sha_commit_target != sha: continue
        tag_name = refname.replace("refs/tags/","")
        if obj_type == "tag":
            try:
                old_tag_raw = subprocess.check_output(
                    ["git","-C",REPO,"cat-file","-p", sha_target], text=True)
            except Exception: continue
            m = re.match(r"^object (\w+)\ntype (\w+)\ntag (.+?)\n", old_tag_raw)
            if m:
                tag_msg = old_tag_raw.split("\n\n", 1)[1] if "\n\n" in old_tag_raw else ""
                env = os.environ.copy()
                env["GIT_AUTHOR_NAME"]  = "Lorenzo-SF"
                env["GIT_AUTHOR_EMAIL"] = "Lorenzo-SF@users.noreply.github.com"
                env["GIT_COMMITTER_NAME"]  = "Lorenzo-SF"
                env["GIT_COMMITTER_EMAIL"] = "Lorenzo-SF@users.noreply.github.com"
                idx = rewritten.index(sha)
                a_dt = datetime.datetime.fromtimestamp(new_comms[idx], tz=TZ).astimezone(datetime.timezone.utc)
                env["GIT_AUTHOR_DATE"]    = a_dt.strftime("%Y-%m-%dT%H:%M:%S+00:00")
                env["GIT_COMMITTER_DATE"] = a_dt.strftime("%Y-%m-%dT%H:%M:%S+00:00")
                subprocess.run(["git","-C",REPO,"tag","-d",tag_name], stderr=subprocess.DEVNULL)
                subprocess.run([
                    "git","-C",REPO,"tag","-a",tag_name,new_sha,"-F","-"
                ], env=env, input=tag_msg, text=True, check=True)
                print(f"  retag (ann): {tag_name} → {new_sha[:8]}", file=sys.stderr)
        else:
            subprocess.run(["git","-C",REPO,"tag","-f",tag_name,new_sha],
                          check=True, stderr=subprocess.DEVNULL)
            print(f"  retag (light): {tag_name} → {new_sha[:8]}", file=sys.stderr)

print(f"DONE. {len(rewritten)} rewritten.", file=sys.stderr)
```

Uso: `python3 rewrite_dates3.py /path/to/repo [since-date]`

**Limitaciones conocidas**:
- Skips merge commits (multi-parent) con warning. Para esos, hay que resolverlo a
  mano después.
- Si dos nuevos timestamps colisionan, el segundo += 1 seg (el `mono()` fix).

---

## 14. Bug triaging list (todo lo que el usuario reportó y arreglamos)

### Delfos:

✅ **Ecto repo lookup fallaba**: corregido en alaja v0.3.12 (`dispatch_main/1` llama
`Application.ensure_all_started(__otp_app__())`)
✅ **NIF no se incluía en binario release**: corregido con `batamanta: [format: :release]`
✅ **DB name "delfos_prod"**: cambiado a `"delfos_dev"` por default en `config/prod.exs`
✅ **PostgreSQL 16**: actualizado a 17 en `setup/db.ex`
✅ **pgvector no instalado**: instalado via `Ecto.Adapters.SQL` desde Repo
✅ **Migraciones no aplicadas**: `Ecto.Migrator.with_repo/3` + auto-migrate en
  `Application.start/2`
✅ **`delfos setup db/llm` ignoraba args**: ahora acepta `["db" | rest]` o `["llm" | rest]`
✅ **Docker container conflict**: resuelto con `maybe_recycle_existing_container/1` que
  pregunta al usuario
✅ **Doctor spam Postgrex**: layout estructurado con secciones
✅ **Doctor structured output**: ahora agrupa por [Postgres] [TreeSitter] [Models] [Config]
✅ **Tree-sitter cargo conflict**: `tree-sitter-perl` quitado (causaba conflicto con
  tree-sitter 0.25 vs 0.26); `tree-sitter-kotlin` mantenido fuera (no soportado en
  tree-sitter 0.25)

### Pendiente de esta sesión:

⚠️ **Más lenguajes al tree-sitter NIF**: usuario dijo "quiero todo lo que pueda estar
  en tree-sitter, se haga con tree-sitter". Candidatos:
  - `kotlin` (fork: tree-sitter-kotlin-ng)
  - `r` (tree-sitter-r)
  - `powershell` (tree-sitter-powershell)
  - `assembly` (tree-sitter-asm)
  - `groovy` (tree-sitter-groovy)
  - `fsharp`, `vb`, `objective-c` (forks comunitarios)

---

## 15. Reglas de estilo y formato

**No obviar**:

- Mensajes de commit en **inglés**, formato conventional commits (`fix(scope):`, `feat:`, `chore:`, `docs:`, `test:`, `refactor:`)
- Mensajes de chat con el usuario en **español**
- Líneas de código ≤ 120 cols
- Indentación con 2 espacios (Elixir estándar)
- Importes ordenados alfabéticamente en bloques `alias` (credo strict lo exige)
- Tests: describir el comportamiento, no la implementación
- Cuando haya duda entre "mejor código" y "funciona", priorizar funciona (este es código
  privado de delfos, no OSS; el usuario es pragmático)

---

## 16. Cosas que NO hacer

1. **No respondas "no puedo hacerlo" sin intentarlo primero**. El sandbox tiene
   limitaciones pero tiene `web_search`, `web_fetch`, herramientas de edición y compilación.
2. **No uses `path:` para dependencias del ecosistema**. SIEMPRE `github: ..., branch: "main"`.
3. **No añadas credenciales hardcoded o secrets en código**. Las API keys van en env vars.
4. **No regeneres git history fake**. La política es REESCRIBIR fechas, no inventar
   commits.
5. **No commitees a la rama principal sin tu propia validación**. Lee primero el diff.
6. **No uses escripts** para releases (batamanta + format: :release). Los escripts no
   pueden incluir Rust NIFs.
7. **No le pongas `--warnings-as-errors` al CI de delfos**. Crea falsos positivos.
8. **No uses `--cover`** en CI de delfos. Crea dependencia con Coveralls token.

---

## 17. Modo de trabajo con el usuario

- **El usuario es muy detallado y quiere SOLIDEZ**. No improvisa. Cuando da feedback
  sobre un bug, vale la pena arreglar todos los relacionados, no solo el que mencionó.
- **El usuario es pragmático**, no quiere test coverage del 100%, no quiere docs exhaustivos.
  Quiere que **el código funcione y los tests prueben los flujos críticos**.
- **Es un buen observador**: si encuentra un bug colateral mientras prueba otra cosa,
  va a preguntar "¿qué pasa con X?". No ignores esos reportes.
- **Si una decisión de diseño no está clara, pregunta explícitamente antes de elegir**.
  No improvises cosas como "voy a usar X porque parece mejor" — el usuario prefiere
  que le preguntes.

---

## 18. Próximos pasos sugeridos (orden de prioridad)

1. **Añadir tree-sitter grammars faltantes** a `native/tree_sitter_nif/Cargo.toml`:
   - r, powershell, assembly, groovy, objective-c (los más comunes)
   - kotlin via fork (`tree-sitter-kotlin-ng` u otro compatible con 0.25)
   - fsharp, vb solo si encuentras forks compatibles
2. **Tests para los 12 commands sin tests**. Empezar por `query`, `audit`, `explain`
   (los más usados).
3. **Wire highlighting** en `explain`, `audit`, `query` para que rendericen código con
   colores via `Alaja.Syntax.highlight_content/2`.
4. **TUI framework** (proyecto aparte) —solo después de que delfos esté estable.

---

## 19. Archivos críticos en delfos (memoria del path)

- `lib/delfos/cli.ex` — DSL entry point
- `lib/delfos/cli/commands/{init,scan,query,audit,summarize,explain,graph,context,doctor,status,config,integrate,models,setup}.ex`
- `lib/delfos/cli/commands/setup/{db,llm}.ex`
- `lib/delfos/application.ex` — auto-migrate en `start/2`
- `lib/delfos/parsers/dispatcher.ex` — ext → language
- `lib/delfos/parsers/treesitter/tree_sitter.ex` — NIF binding
- `lib/delfos/parsers/generic_parser.ex` — regex fallback
- `lib/delfos/syntax/` — 67 archivos de lenguajes
- `lib/delfos/syntax/registry.ex` — `Delfos.Syntax.Registry.register_all/0` (llamado en `Application.start/2`)
- `lib/delfos/llm/candil_bridge.ex` — provider wiring
- `lib/delfos/mcp/server.ex` — async stdin reader
- `lib/delfos/repo_starter.ex` — wrapper que inicia Repo on-demand
- `lib/delfos/health.ex` — periodic health check
- `lib/delfos/config/manager.ex` — JSON config + AES-256-GCM
- `native/tree_sitter_nif/Cargo.toml` — 27 grammars
- `native/tree_sitter_nif/.cargo/config.toml` — macOS `dynamic_lookup` rustflag
- `priv/repo/migrations/` — 10 migrations (HNSW indexes incluidos)
- `mix.exs` — `batamanta: [format: :release, binary_name: "delfos"]`,
  `gen: ["batamanta", "deploy"]`

---

## 20. Final

Si has leído hasta aquí y todo tiene sentido, ya tienes el contexto que yo tenía
después de varias sesiones con el usuario. Las claves que NO debes olvidar:

1. **Las fechas de git siempre en ventana 20:00-02:00 Berlin**, salvo finde.
2. **Las deps del ecosistema van a `branch: "main"`**, no a tags ni a paths.
3. **El usuario habla español**, **el código habla inglés**.
4. **El foco inmediato es delfos**; todo lo demás es secundario hasta que delfos esté "digno de CV".
5. **Si algo es ambiguo, pregunta antes de implementar**. No improvises arquitectura.

Buena suerte en la nueva sesión.
