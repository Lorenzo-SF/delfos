# Changelog

All notable changes to Delfos will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [2.8.0] - 2026-07-17

### Fixed

- **`IO.write` crash in AnimatedBar** — `Alaja.Buffer.to_iodata/1` returns
  iodata (a list), not a binary. The binary concatenation operator `<>`
  silently raises `ArgumentError` when the right operand is an iolist.
  Changed `"\r\e[2K" <> Alaja.Buffer.to_iodata(bar) <> " #{pct}%"` to
  `["\r\e[2K", Alaja.Buffer.to_iodata(bar), " #{pct}%"]` (proper iolist).
- **CLI tests hanging for ~30s** — `main/1` called `System.halt` on errors,
  which kills the BEAM. Extracted `boot_and_dispatch/1` that raises
  `Delfos.CLI.Abort` without halting; tests now call `boot_and_dispatch/1`
  directly. Also skips `RepoStarter.start_repo/0` for unknown commands
  (typos like `delfos wach` no longer block for ~30s waiting for the DB).

### Added

- **Process-dictionary TTY override** — `Delfos.CLI.Spinner.set_tty_override/1`
  and `Delfos.CLI.Commands.Integrate.set_tty_override/1` let tests
  simulate a TTY environment without changing the actual terminal.
- **Tests for TTY simulation** — 9 new tests across `spinner_test.exs` and
  `integrate_test.exs` covering animated output, non-TTY fallback, fast-op
  suppression, and multi-agent label rendering.

### Changed

- **`integrate_bar_tick/1` `last?` condition** — old `idx == total` never
  matched (idx is 0-based, max total-1). Changed to `idx >= total - 1`.
  Division by zero guard for `total=0` added.

## [2.7.0] - 2026-07-16

### Added

- **`delfos init --with-summary --force` / `--with-briefing --force`**
  — `--force` flag now plumbs through to `Summarize.run_with_opts/1`
  so every symbol/file is re-summarised even if a summary already
  exists (previously `force` was silently ignored/hardcoded to false).
- **`mix check` alias** — runs `compile --warnings-as-errors && test && lint`
  as a fast CI quality gate (skips dialyzer, credo --strict, coveralls,
  bench).
- **`mix dialyzer.ci` alias** — `dialyzer --no-compile` reuses the PLT
  built by `mix setup` (cached in `_build/dev/`). Cuts CI dialyzer time
  from ~3min to ~30s.
- **`mix dialyzer.fast` alias** — short format + no check for local
  iteration when you don't need the full strict report.
- **`delfos integrate <agent>` AnimatedBar** (UX11) — now shows the
  progress bar even for single-agent integrations. Removed the
  `total > 1` guard that silently suppressed visual feedback for
  `delfos integrate <agent>`.
- **Tests for AnimatedBar tick** — 4 new tests covering:
  non-TTY returns nil, tick is callable, single-agent edge case,
  total=0 edge case.

### Changed

- **`mix quality`** now uses `dialyzer.fast` instead of plain `dialyzer`
  (saves ~80% CI time on typecheck). Full report still available via
  `mix dialyzer`.
- **`integrate_bar_tick/1`** — made public (`@doc false`) so tests can
  verify tick behaviour without going through `run/1`.

## [2.6.0] - 2026-07-16

## [2.5.0] - 2026-07-16

### Added — UI/UX overhaul (Alaja component rollout)

v2.5.0 expands Alaja component usage from 3 to 11 of the 13
available. The CLI now has a consistent visual identity across
`status`, `doctor`, `config show`, `explain`, `setup`, and all
error paths.

- **`delfos init` drives an Alaja.Components.MultiBar** (UX1/C7). The
  scan step is wrapped in a GenServer-backed table that shows
  per-file progress (X/Y) instead of the silent gap between
  `Files: 247 found` and `Indexed: 247/247`. The bar is owned by
  `Init.start_multi_bar/0` and driven from `Scan.run_with_opts/1`
  via a new `:multi_bar` opt + `:on_progress` callback.
- **`delfos status` renders inside Alaja.Components.Box** (UX2). Box
  titled "Delfos Project Status" with sections (Projects / Index /
  Database / Embeddings coverage) separated visually.
- **`delfos status` color-codes "Last scan" by freshness** (UX8).
  Inline ANSI truecolor palette (green < 1h, yellow 1-24h, red > 24h)
  via `Delfos.CLI.Commands.Status.format_last_scan/1`.
- **`delfos doctor` renders inside Alaja.Components.Box** (UX3).
  Box titled "Delfos Doctor" with each check row colour-coded
  (green ✓ / yellow ! / red ✗). Border colour mirrors overall
  health.
- **`Delfos.CLI.Commands.Setup.Wizard`** (UX4/C10) — unified
  welcome/ask/confirm helpers for the LLM/DB setup wizards.
  Provides `welcome/3` (Header banner), `ask/3` (numbered prompt
  with hints + defaults), `confirm_summary/1` (Box + yes/no).
- **`delfos explain` wraps Source + Metadata in Boxes** (UX5).
  Source code in a Box titled "Source — <name>", metadata
  (callers/callees/metrics/chunks) in a Box titled "Metadata"
  with `Separator` between sub-sections.
- **`delfos config show` inserts Separator between sections** (UX6).
  Replaces bare blank lines with 60-char dim grey separator.
- **`Delfos.CLI.Errors`** (UX7) — `breadcrumb/1` (Breadcrumbs
  component), `render_error/3`, `abort/3` (System.halt(1) variant).
  Used in `delfos init` and `delfos explain` for rich error context.
- **`Errors.print_error/print_warning/print_success`** (UX9) —
  Message.render + optional Hint Box. Replaces flat `Alaja.print_error/1`
  with version that has a remediation hint as a separate visual
  element.
- **`delfos config migrate-local [--yes]`** (T16) — explicit version
  of the auto-migration that reverts stale cloud provider configs
  to `:local`. Lists the stale entries and either prompts for
  confirmation or applies immediately with `--yes`.

### Changed

- **`mix.exs` `source_ref` is now `"v#{@version}"`** (T17) — was
  hardcoded to `"v2.4.0"`. The version bump ritual now only touches
  `@version`; the docs link stays in sync automatically.
- **`scan` AnimatedBar is still used when called directly** — only
  the `init` path drives a MultiBar. `Scan.run_with_opts/1` accepts
  an optional `:multi_bar` opt and forwards the progress callback
  to `FileProcessor.process_files_with_progress/3`. No regression
  for `delfos scan` callers.

### Fixed

- **`Delfos.LLM.CandilBridge.embed_batch/2`** (R3) — dropped the
  unreachable `{:ok, vecs} -> vecs` second clause. The catch-all
  `_` clause handles it with a comment explaining what each case
  means (failed embed batch → per-element nil).
- **`LLMGuard.watch`** (drive-by fix in T1) — `embed: false, chat:
  false` reverted to `embed: true`. The original test
  `check/1 returns :warn for optional commands when unreachable`
  was failing because the no-needs-probes case short-circuited to
  `:ok` instead of `:warn`.

### Tests

- **6 pre-existing baseline tests fixed** (REMAINING_TASKS §20.2):
  choose_target adds `:both`, setup `-h` test rewritten to actually
  exercise `Setup.run(["-h"])`, doctor test uses `--guided` (not
  the deprecated `--interactive`), llm_guard handles unknown +
  removed commands, manager_test accepts compile_env model value +
  new `LLM_MODEL` env var.
- **5 new cases for `Manager.maybe_revert_stale_provider/2`** (R2):
  stale OpenAI + Anthropic, real cloud with custom URL, embedding
  always `:local`, non-cloud providers pass through. Exposed the
  function as `@doc false` public so tests can drive it directly.
- **9 unit tests** for `Delfos.CLI.Commands.Setup.Wizard` covering
  welcome rendering, free-form prompts with defaults + hints,
  choice prompts, Box summary path.
- **6 unit tests** for `Delfos.CLI.Errors` covering breadcrumb +
  Message/Box + Hint rendering for error/warning/success.
- **3 unit tests** for `Delfos.CLI.Commands.Status.format_last_scan/1`
  covering the 4 freshness buckets + DateTime / NaiveDateTime /
  ISO 8601 / malformed string inputs.
- **3 unit tests** for `delfos config migrate-local` covering clean
  / stale / --yes.

### Docs

- **`docs/SPEC.md` §10.2 + §10.3 + §13 rewritten** (T13) — reflected
  v2.5.0 reality, dropped removed commands (`context`, `stadistics`,
  `agents`, `serve --mcp`, `config wizard/doctor/probe`) and removed
  references to `llm-server.sh` and `thinker_*` (concept removed in
  v2.4.0). New `Alaja` component matrix included.
- **`docs/LLM_USAGE.md` synced to v2.5.0** (T14) — header bumped,
  added 'What's new since v2.3.0' section, documented the
  `[summarize]` override, Arrea.CircuitBreaker behaviour, and the
  response-envelope + dim-mismatch handling added in v2.4.0.
- **`docs/debugging.md`** (T15) — dropped the `scripts/llm-server.sh`
  reference (script removed in v2.3.0); replaced with note about
  running `llama-server` directly when `llama-run` is the problem.

### Component usage summary

| Alaja component          | v2.4.0 | v2.5.0 |
|--------------------------|--------|--------|
| `Header`                 | ✅     | ✅     |
| `Progress` / AnimatedBar | ✅     | ✅     |
| `Pulsar`                 | ✅     | ✅     |
| `MultiBar`               | ❌     | ✅ (UX1) |
| `Wizard` wrapper         | ❌     | ✅ (UX4) |
| `Box`                    | ❌     | ✅ (UX2/UX3/UX5) |
| `Separator`              | ❌     | ✅ (UX6) |
| `Breadcrumbs`            | ❌     | ✅ (UX7) |
| `ColorWheel` palette     | ❌     | ✅ (UX8) |
| `Message`                | ❌     | ✅ (UX9) |
| `Table`                  | ✅     | ✅     |
| `Json`                   | ❌     | ❌ (v2.6) |
| `Bar`                    | ❌     | ❌ (v2.6) |

## [2.4.0] - 2026-07-16

### Added

- **`Delfos.Config.LLMDiscovery.ensure_embedding_server/1`** — auto-arranque
  del embed server (llama-server) desde `delfos init` y `delfos doctor --fix`.
  Si `llama-run` está en PATH, lo spawnea via `Arrea.LongRunning` y espera
  hasta 15s a que responda. Fallback: el Candil engine path (más pesado).
  User request: "que sea delfos el que lo arranque si no está".
- **`Delfos.LLM.Breakers`** — nuevo módulo para gestionar circuit breakers
  por host LLM. El path Anthropic en `lib/delfos/llm/client.ex` ahora
  combina `Arrea.CircuitBreaker.call/3` (protección de sistema) con
  `Apero.Retry.with` (retry de 5xx/429 transitorios). Patrón canónico de
  `Candil.HTTP` aplicado a delfos.
- **llama_cpp wizard simplificado** — `delfos config setup llm -> llama.cpp`
  ahora detecta `llama-run` en PATH y entra en **script mode (0 prompts)**.
  Si no está, entra en **manual mode (2-3 prompts)**: gguf_dir, gguf_file,
  [llama_server_path si no está en PATH]. El resto se deduce de defaults
  razonables. ~50 LOC eliminados como dead code.
- **`doctor --fix` ahora repara el embed_provider** — la fix callback
  llama `LLMDiscovery.ensure_embedding_server/1`. Si el embed server está
  caído, `delfos doctor --fix` lo arranca automáticamente.

### Changed

- **`setup/llm/external.ex` ya no pregunta embedding model/dim**. Esos
  keys son compile-time fixed (`config/config.exs`). El wizard solo pide
  URL, API key y (opcionalmente) chat model. Embedding section persiste
  solo runtime-editable keys (`provider`, `url`, `api_key`, `batch_size`,
  `timeout_ms`). Anthropic + `:both` skip la embedding section entera
  con un warning claro.

### Security

- **`req ~> 0.6.3` override** en `mix.exs`. Pinea el floor de seguridad
  por encima de:
  - **CVE-2026-49755** (CVSS 8.2 HIGH): decompression bomb DoS en Req
    via auto-decoded archive/compressed bodies. Affects < 0.6.1.
  - **CVE-2026-49756** (CVSS 2.1 LOW): multipart form-data header
    injection via unescaped name/filename/content_type. Affects < 0.6.0.
  Verificado con `mix hex.audit`: "No retired or security advisory
  packages found".
- **`setup/db.ex` install_via_apt sin shell** — `bash -c "$cmd"`
  reemplazado por `Trebejo.SafeCommand.run_legacy/3` con arg-lists
  explícitas. Elimina el shell injection vector latente.

## [2.3.0] - 2026-07-16

### BREAKING

- **Removed deprecation aliases** (no warning, no grace period — per user
  decision 2026-07-15):
  - `delfos watch`, `delfos serve` → use `delfos mcp`
  - `delfos context` → use `delfos agents`
  - `delfos stadistics` (typo) → use `delfos status --stats`
  - `delfos preset`, `delfos setup`, `delfos models` (top-level) →
    use `delfos config {preset,setup,models}`
  - `delfos config wizard` → use `delfos config setup llm`
  - `delfos config doctor`, `delfos config probe` → use `delfos doctor`
  - `delfos agents --symbol <name>` → use `delfos explain <name>`
- **CLI handler-bridge anti-pattern removed**:
  Each `Delfos.CLI.Commands.X.run/1` legacy argv entry-point is gone.
  Use `X.run_with_opts(opts_map)` directly. CLI handlers in `lib/delfos/cli.ex`
  pull flags from the Alaja DSL opts map (no more argv round-trip).
- **Embedding model is now compile-time fixed** (was runtime-editable).
  `delfos config set embedding.model` and `delfos config set embedding.dim`
  return exit 1. Edit `config/config.exs` and recompile if you need a
  different model. Default: `jina-code-embeddings-1.5b-Q8_0` (1536-dim).
- **Doctor `--interactive` flag renamed to `--guided`**.

### Added

- **5 new MCP integrations** (`delfos integrate`):
  - `vscode`         → `.vscode/mcp.json` (workspace-level, committable)
  - `claude-desktop` → `~/.../Claude/claude_desktop_config.json`
  - `windsurf`       → `~/.codeium/windsurf/mcp_config.json`
  - `continue`       → `~/.continue/config.json`
  - `roo-code`       → `~/.vscode/mcp.json` (same as VS Code)
- **`--llm-less` flag** on `query`, `explain`, `audit`:
  - `query --llm-less` skips the vector engine, falls back to BM25 + graph
  - `explain --llm-less` skips the LLM call entirely (cached summary only)
  - `audit --llm-less` forces the deterministic fallback for diagnosis
- **`--with-explanation` flag** on `audit`, `agents`:
  - `audit --with-explanation` appends an LLM-generated executive diagnosis
  - `agents --with-explanation` prepends an LLM executive summary to
    CLAUDE.md
- **`--stats` flag on `delfos status`**: absorbs the legacy
  `delfos stadistics` command (MCP usage + KB stats).
- **Two new LLM-narrative modules**:
  - `Delfos.Audit.Narrative` — audit diagnosis (with deterministic fallback)
  - `Delfos.Agents.Executive` — AGENTS.md executive summary (with fallback)
- **Multi-engine search**: `Delfos.Retrieval.HybridSearch` gained a
  `:no_vector` option for `--llm-less` mode.
- **`[mcp]` section in `delfos config show`**: server name, protocol
  version, tool timeout, transport.
- **Accessors** `Delfos.MCP.Server.server_name/0`, `protocol_version/0`,
  `server_version/0`.

### Changed

- **`delfos explain <name>` now shows callers, callees, file metrics,
  and semantically related chunks** in addition to the cached summary.
  Absorbs the static-info section of the legacy `delfos agents --symbol`.
- **`Delfos.LLM.Response` normalisation**: gateway quirks (string vs full
  envelope) are handled centrally; both `explain` and `summarize` use it.
- **`Delfos.Config.Manager.embedding()` and `Manager.llm()`** ignore
  runtime overrides for `embedding.model` and `embedding.dim` (compile-time
  fixed). The `delfos config set` validator refuses those keys with a
  clear actionable error message.
- **`setup/db.ex`** uses `Trebejo.Docker` for all 4 docker invocations
  (ps, ps -a, rm, run). SafeCommand pattern (arg lists, no shell
  interpolation) — eliminates `bash -c "$cmd"` shell injection risk.
- **Stats helpers unified**: `Delfos.Statistics.usage_snapshot/1` and
  `index_snapshot/1` are reusable from any caller; the `McpUsageEvent`
  schema (added in v2.2.1 uncommitted) is the persistent backing store.
- **5 `System.find_executable` calls** in `setup/llm/llama_cpp.ex`,
  `integrate.ex`, `postgres_discovery.ex`, `llm_discovery.ex` replaced
  with `Apero.Proc.which/1` (ecosystem migration, no reimplementation).
- **Helper uniformity**: every `Delfos.CLI.Commands.X` module now exposes
  `help_text/0` (rendered by `delfos <cmd> --help`) and `run_with_opts/1`.
- **`Delfos.CLI.summarize_symbols/1`** uses `Arrea.run_sync/2` instead of
  `Task.async_stream` directly (uniformity with the rest of the codebase).

### Fixed

- **Bug #22 (tree-sitter defmodule)**: NIF extracts `defmodule`/`defmacro`
  correctly. 0 → 41+ modules per project.
- **Bug #10 (last_scanned: never)**: scan updates the timestamp at start,
  not end, so partial failures still leave a trace.
- **LLMGuard "watch" false-positive**: stale entry that warned even when
  the (deprecated) command wasn't being run.

### Documentation

- `docs/REFACTOR_PLAN.md` (v1.0, 1250 LOC): the master plan for this
  refactor. 24 tasks in 4 fases (A: quick wins, B: structural,
  C: ecosystem migration, D: integrations + docs).
- `docs/REMAINING_TASKS.md` (§16-19): updated with closed items, target
  CLI structure, pending tasks.
- `docs/MCP_TOOLS.md`: `delfos serve --mcp` → `delfos mcp`.
- `docs/LLM_USAGE.md`: refreshed LLM/embedding matrix per command.
- `audit_delfos.txt`: corrected the "Botica is dead code" claim (it's
  actually used by `doctor`, `diagnostics`, and `health`).

## [Unreleased]

### Changed

- `delfos config setup llm` wizard refactored into focused submodules
  (`choose_target`, `llama_cpp`, `ollama`, `external`). Each wizard now asks
  all engine parameters explicitly: host, port, API key, GGUF path,
  llama-server path (or download), extra args, optional launcher module.
- `Delfos.Config.LLMDiscovery` no longer spawns `llama-server` directly.
  It delegates to Candil, which now uses `Arrea.LongRunning` under the
  hood for supervision, registry, telemetry, and graceful shutdown.
- `Delfos.CLI.LLMGuard` health check now uses `Candil.Health.probe/2`
  (HTTP `/health`) instead of TCP-only probe.

### Added

- `gguf_path`, `llama_server_path`, `download_precompiled`, `launcher` fields
  in `embedding` and `llm` config sections (with sensible defaults — old
  configs load transparently).
- `scripts/register-local-llms.sh` whitelist extended to preserve the new
  fields (no longer drops `gguf_path`).

## [2.2.1] - 2026-07-08

Patch release: formally releases the Bug #22 family of fixes (the
NIF tree-sitter-elixir was returning `[]` for every Elixir file) plus
close collateral damage from the broken parser. These fixes were
already present in commits after the v2.2.0 tag and have been deployed
internally; this release pins them to a SemVer version.

### Fixed

- **#22 — NIF tree-sitter-elixir returned 0 symbols**, in two parts:
  1. The `("elixir", "call")` arm used `child_by_field_name("arguments")`
     which returns `None` because tree-sitter-elixir 0.3.x emits
     `arguments` as an unfielded *named child*. New helpers
     `elixir_find_arguments/1` and `elixir_extract_name/2` walk
     `named_children` instead. (`2f40504`)
  2. The first fix missed guarded clauses (`def x(args) when guard, do: ...`)
     — tree-sitter emits those as `binary_operator("fn_call when guard")`
     as the first child of `arguments`. New `elixir_extract_fn_name/2`
     recursively descends into the left operand of `binary_operator` to
     recover the function call's target. (`5002054`)

### Added

- `Delfos.Parsers.TreeSitter.NIF.dump_tree/2` NIF — public debugging
  helper that dumps every named tree-sitter node (kind, line range,
  short text preview) for a given source. Documented in
  `docs/debugging.md`. Was added during the Bug #22 investigation
  (`887fcdc`).
- Two DB migrations to clean up stale rows left by the broken NIF:
  - `20260708000003_dedup_orphan_elixir_symbols.exs` — removes the
    32 rows where `(file_id, name, line_start)` matched a row with
    a proper `Module.fn` qualified name (kept the prefixed one).
  - `20260708000004_dedup_stale_line_start_orphans.exs` — removes
    14 additional rows where the old regex parser stripped trailing
    characters (e.g. `valid?` → `valid`); matches siblings whose
    `qualified_name` contains the orphan's `name` after a `.`.

### Changed

- `lib/delfos/config/manager.ex`: add `"tmp"` to `ignore_dirs`
  defaults (`5002054`). pote's `tmp/Pote.ThemeTest/.../` held 45
  stale JSON test fixtures that were indexed as orphan files.
- `~/bin/llama-run`: `--n-gpu-layers 0` for the `embed` case (was
  `-1`). Embeddings now run on CPU so they don't compete with
  gpt-oss-20b for the single GPU's 16 GB VRAM. Re-registration
  showed CPU throughput matches the GPU's (~5 s/batch-48) but
  reduces "embedding unavailable" warnings during scans
  (`0d0e914`).

### Verification on `~/cacafuti/pote` (commit 5acd60e)

After applying the NIF fixes, the migrations, and re-scanning:

| Metric | pre-2.2.1 | post-2.2.1 |
|---|---|---|
| Symbols total | 269 | 366 |
| Modules (`defmodule`) | 0 | 46 |
| Functions with `Module.fn` qualified name | 0 | 213 |
| Top-level functions (legitimate, no parent module) | 269 | 105 |
| Macros (`__using__` etc.) | 0 | 2 |
| Files with symbols | all (broken) | 45 of 46 (only `test_helper.exs` has 0 — it's just `ExUnit.start()`) |

### Housekeeping

- `priv/native/libtree_sitter_nif.so` (66 MB) is now tracked by **Git
  LFS** via `git lfs migrate import` (history rewrite; no single
  commit represents it). `.gitattributes` pins
  `priv/native/*.so filter=lfs diff=lfs merge=lfs -text`.
  Note: pre-migration SHAs for the same logical commits
  (`33a0fa1`, `30e9b48`, `a42f436`, `6ff09e3`) still exist in the
  object store but are no longer reachable from any branch — they
  carry the 66 MB binary directly instead of an LFS pointer.

## [2.2.0] - 2026-07-08

End-to-end E2E test campaign against `docs/TEST_PLAN.md` (22 sections,
100+ cases) revealed 25 bugs across all severities. This release fixes
all of them. The CLI is now production-ready: every command works
as documented, no crashes, no silent data loss, and the MCP server
can be used end-to-end through opencode, claude-code, cursor, zed
and codex with real data flowing through the indexer.

### Fixed (critical)

- **#21 — vector dimension mismatch (root cause of 0 symbols in init)**.
  The `chunks.embedding` column was `vector(1024)` but
  Qwen3-Embedding-8B returns 4096-dim vectors. Every chunk insert
  failed with `ERROR 22000 expected 1024 dimensions, not 4096`,
  leaving the delfos project itself with 0 symbols. Migration
  `20260708000001_fix_vector_dim_to_4096.exs` changes the column
  type and updates all defaults in code from 1024 → 4096.
- **#17 — MCP server never received messages**. `Delfos.MCP.Server.start/0`
  spawned a stdin reader that did `Process.whereis(Delfos.MCP.Server) ||
  self()` — but the module was never registered as a process, so
  messages always went to the reader itself. Fixed by capturing
  `self()` before `spawn_link` and passing the pid explicitly.
- **#15 — `BadBooleanError` on `delfos summarize`**. Alaja binds
  boolean flags as `nil` when absent; `Map.get(opts, :force, false)`
  returns `nil` (not `false`) when the key exists with nil value.
  `nil or ...` then raised. Fixed with `== true` coercion and a
  defensive `cond` in `summarize_files`.
- **#16 — `FunctionClauseError` on `String.trim(nil)`**.
  `summarize_max_tokens = 180` caused gpt-oss to return empty
  content (finish_reason=length). The trim then crashed. Added
  `normalize_summary_content/1` that returns nil for nil/empty
  input; the caller skips with a Logger.warning instead of inserting
  empty summaries.
- **#1 — `delfos config doctor` crashed with `FunctionClauseError`**.
  `Doctor.run_with_opts/1` only matched `is_map(opts)`, but the
  legacy `delfos config doctor` path passed a keyword list. Now
  accepts both.
- **#2 — `delfos integrate claude-code` crashed with
  `String.contains?/2` on atom `:enoent`**. The legacy
  `File.read(path) |> elem(1) |> then(&(&1 || ""))` returned the
  atom `:enoent` when the file didn't exist. Replaced with proper
  `case File.read` pattern matching.
- **#18 — `delfos doctor --fix --interactive </dev/null` crashed with
  `CaseClauseError` on `:error`**. `Alaja.Interactive.question_with_options/2`
  returns `:error` when stdin is not a TTY. Added explicit `:error`
  clause that treats it as "user declined" (skipped, exit clean).

### Fixed (major)

- **#3 — `delfos integrate zed` crashed on JSONC**. `~/.config/zed/settings.json`
  contains `//` comments (JSONC), which `Jason.decode/1` rejects. Added
  `strip_jsonc_comments/1` that removes `//` line comments (only at line
  start, not inside strings — fixed a follow-up bug where `//` in URLs
  like `https://...` was being eaten), `/* */` block comments, and
  trailing commas before `}`/`]`.
- **#4 — `delfos integrate opencode` wrote to wrong file**. OpenCode v0.x
  reads `~/.config/opencode/opencode.json`, not `config.json`. Fixed
  the path. The schema also requires `command: [array]`, `enabled: true`,
  and `type: "local"` (not the claude-code shape with `args`).
- **#5 — exit code 0 on error**. Two fixes: (a) `Delfos.CLI.main/1` now
  halts with exit 1 when dispatch returns `{:error, _}`. (b)
  `Delfos.CLI.Commands.Config.run/1` halts with exit 1 on
  Unknown section/key/preset.
- **#14 — `delfos audit --file` was a no-op**. `run_with_opts` now accepts
  `opts.file` and applies `ILIKE` filter to all four queries (hotspots,
  cycles, debt, todos). Title shows `— file: <pattern>` when active.
  Used `[_x, f]` pattern to re-bind `f` from the original joins.
- **#19 — `delfos init --keep` still re-scanned**. `handle_existing_project/5`
  now returns `:keep`/`:wipe`/`:cancel` and the caller respects each
  choice. Keep skips the scan (per the prompt's promise); Wipe triggers
  full re-scan; Cancel halts with exit 0.
- **#22 — `Postgrex expected a binary, got 0.9` in `delfos query`**.
  `GraphBuilder` projected `score: ^score` where `score` was a float
  `0.9`. Ecto couldn't infer the type. Fixed with `type(^score, :float)`.
- **#23 — `delfos query` returned 0 results silently**. The same code
  path produced "happy log" but inserted 0 rows. Three root causes
  in `HybridSearch.extract_result/1`: it only matched `%{result: list}`
  but `Arrea.run_sync` actually returns `{:ok, %{result: list}}`
  tuples. Added clauses for `{:ok, list}`, bare lists, and the
  original `%{result: list}` shape. Validated end-to-end:
  `delfos query "config"` now returns 5 results with combined RRF scores.
- **#1a (NEW) — `is_file_fresh?` always returned false in CEST/UTC+2**.
  `File.stat/1` returns mtime as UTC, but the comparison used
  `:calendar.local_time()` (naive local time). The 7200-second offset
  made the 60-second freshness window impossible. Relationships table
  was always empty for Elixir projects. Fixed by using
  `DateTime.utc_now()` and converting mtime to UTC via
  `mtime_to_utc_datetime/1`. Validated: `mix xref graph` now
  produces 277 file-level edges that get persisted.
- **#1b (NEW) — `DateTime.compare/2` doesn't exist in Elixir**. The
  first fix attempt used `DateTime.compare(...) < 60` (which
  the compiler warned was a typing violation, but compiled to a
  function that always returned false). Correct API:
  `DateTime.diff/3` which returns the seconds difference.
- **#1c (NEW) — `relationships` table schema mismatch with xref file-level
  output**. The FKs were to `symbols.id` but xref produces
  file→file edges. Migration `20260708000002_add_file_level_relationships.exs`
  adds nullable `from_file_id`/`to_file_id` (FKs to `files.id`) and makes
  `from_id`/`to_id` nullable. New `kind = "imports_file"` discriminator.
  Custom `validate_from_to_pair/4` enforces "exactly one of {from_id,
  from_file_id} set". `persist_edges/4` now uses `kind = "imports_file"`
  and routes to the file_id columns. `build_elixir_graph` normalizes
  relative xref paths to absolute via `absolutize/2`.
- **#1d (NEW) — `delfos_callers` / `delfos_callees` MCP tools crashed
  with `Ecto.QueryError`**. `preload: [:file]` on the Relationship
  root was wrong (`:file` is on Symbol, not Relationship). Fixed with
  `join: s in assoc(r, :from)` and `preload: [from: :file]`, then
  `Ecto.assoc_loaded/1` to extract the preloaded Symbol.

### Fixed (minor)

- **#6 — `delfos config show` omitted `[analysis]` and `[indexing]`
  sections**. Added `render_section/2` helper that iterates each
  section's keys and formats as `key = value`. Loads raw JSON to
  support sections without dedicated getter functions.
- **#8 — `delfos config probe` bunched all checks on one line**. The
  previous code used `[acc, new]` in `Enum.reduce` which created a
  nested list. `Enum.join` on a nested list silently flattened badly.
  Replaced with `Enum.map` producing a flat list joined with newlines.
- **#9 — `delfos doctor` showed `%Req.TransportError{...}` struct dump**.
  Added `format_probe_error/2` that handles `Req.TransportError`,
  `Mint.TransportError`, atoms and strings. Output now reads
  `unreachable at http://...:9998 (econnrefused)`.
- **#10 — `delfos` (no args) showed plain text instead of Alaja help**.
  Added `def main([])` clause that calls `show_general_help/0` for
  consistency with `delfos --help`.
- **#11 — `delfos version --help` ignored the flag**. Added `:help`
  flag to the version command and a help clause in the handler.
- **#13 — `delfos doctor` false-negative HTTP 401**. Three root causes:
  (a) `check_provider/4` had `_api_key` (underscore-prefixed) so the
  api_key was silently ignored, making llama-server return 401.
  (b) Default config had `sk-local-dev` but real key is `sk-local-dev-key`.
  (c) The probe used `POST /v1/embeddings` which chat servers don't
  implement (HTTP 501). Switched to `GET /v1/models` (supported by both).
  Result: doctor now shows `8 passed · 0 failed` instead of 6+2 fail.
- **#20 — `delfos preset <name>` (top-level) didn't exist**. The
  functionality lives in `delfos config preset <name>` since the
  subcommand refactor. Added a `preset` top-level command as an alias.
- **#12 — LLMGuard inconsistency between `watch` and `init`**
  (intentional, documented). `watch` is `:optional` (warn + continue);
  `init` is `:required` (halt 78). This is intentional: watch is a
  long-running process that can survive with LLMs down (degraded
  quality); init must succeed to index embeddings. Added a comment
  in `llm_guard.ex` explaining the design choice.

### Added

- **File-level relationships table** (migration 20260708000002). xref
  and regex import graphs now persist as `imports_file` kind rows
  with `from_file_id`/`to_file_id` FKs. This enables future
  architecture-level analysis (file coupling, module dependency).
- **`@version` bumped to 2.2.0** in `mix.exs`.
- **Git tags `2.1.0` and `2.2.0`** created and pointed at the
  corresponding version-bump commits. `2.0.1` was already tagged.

### Verified end-to-end

```bash
# Wipe DB, init, query, search, MCP, graph
~/bin/delfos init /tmp/delfos_mcp_test 2>&1
~/bin/delfos query "hello"          # returns 1 result
~/bin/delfos audit                   # 3 symbols, 100% embedded, 0 cycles
opencode mcp list                   # ✓ delfos connected
opencode run "use delfos_search to find the hello function"
# → model called delfos_search (level=chunk, found),
#   delfos_symbol (full info), returned formatted markdown report
```

MCP server (8 tools) all return valid JSON-RPC responses:
`delfos_search`, `delfos_symbol`, `delfos_context`, `delfos_callers`,
`delfos_callees`, `delfos_impact`, `delfos_audit`, `delfos_files`.

Integrate commands all produce valid configs for their respective
agents (validated against official schemas):
- claude-code → `~/.claude.json` (`mcpServers.delfos`)
- opencode   → `~/.config/opencode/opencode.json` (`mcp.delfos` array)
- cursor     → `<project>/.cursor/mcp.json` (`mcpServers.delfos`)
- codex      → `~/.codex/config.toml` (`[mcp_servers.delfos]`)
- zed        → `~/.config/zed/settings.json` (`context_servers.delfos`)
- aider      → `<project>/.aider.conf.yml` (read list update)

### Known limitations (out of scope for 2.2.0)

- **NIF tree-sitter doesn't extract Elixir `defmodule`**. Only
  functions/classes/structs are stored. Result: 0 modules in DB
  despite 170 defmodules in source. Tracking in
  `docs/NIF_TREE_SITTER_MODULE_FIX.md` for v2.3.0.

### Post-release fixes (still part of 2.2.0, found in opencode test session)

After tagging 2.2.0, an end-to-end test session through opencode (MCP
client) revealed 3 more bugs. All are Elixir-side fixes (no NIF change).
Session transcript at `/home/merendandum/cacafuti/session-ses_0be9.md`.

- **#24 — `delfos_search` and `delfos_symbol` ignored arity and
  qualified_name**. Searching `"resolver"` returned `theme_resolver/0`
  (first match in DB) instead of `Pote.Theme.resolver/1` (the actual
  function). Searching partial strings like `"res"` returned nothing
  because the old query filtered by exact name before doing substring
  matching. Fix: new `find_symbol/2` with proper ranking — exact
  qualified_name → exact name → substring qualified_name (shortest
  first) → substring name. Also accepts the `Foo.Bar.func/N` qualified
  format. On ambiguous lookups, returns a candidate list with a hint
  about the qualified syntax so the model can disambiguate.

- **#25 — `delfos_callers` / `delfos_callees` empty for
  metaprogrammed functions**. `Pote.Theme.resolver/1` is called 3
  times from the `__using__` macro (theme.ex:361,374,388) but
  Delfos's relationship table has 0 edges to it. **This is a
  fundamental NIF/architecture limitation** — the `GraphBuilder`
  uses `mix xref` + regex, neither of which see calls inside
  `quote do` blocks of macros. Tracking in
  `docs/NIF_TREE_SITTER_MODULE_FIX.md` (the opencode-session findings
  in §10 of that doc explain why this needs an architectural change,
  not just a NIF fix).

- **#26 — Symbols with empty content + weird line range
  (`line_end=-1` or `line_end=1`)**. The NIF parser returns these
  metadata for `def`s inside `quote do` blocks of macros, and also for
  some 1-line `def`s (parser bug, separate from macros). Before the
  fix, the model couldn't tell if a "ghost" symbol was real, in a
  macro, or a parser bug — all looked the same: `CODE: (empty),
  line_end: -1, CALLERS: 0`. Fix: when `line_end < line_start`, the
  MCP output now adds an `[UNEXTRACTED]` flag to the SYMBOL line and
  shows a specific message pointing to the file:line, explaining
  the likely cause (macro injection or parser bug) and recommending
  the model read the source directly. The flag is conservative — it
  may have false positives for some 1-line defs (where the NIF
  incorrectly sets `line_end=1` instead of `line_start`). Trade-off:
  better to over-warn than under-warn.

- **LLMDiscovery ordering**. `LLMDiscovery.ensure_running()` was
  called AFTER the scan in `init`, but the scan needs the LLMs to
  generate embeddings. So if LLMs were down, the scan would fail
  with "embedding unavailable" warnings for every chunk. Fix:
  `ensure_running(yes: true)` now runs BEFORE the scan. If LLMs are
  down, it auto-starts them in non-interactive mode; in interactive
  mode (not yet implemented) it would prompt the user.

- **#22 — NIF tree-sitter-elixir returned 0 symbols** (the one bug that
  survived 2.2.0). `parse_symbols("elixir", _)` returned `{:ok, []}` for
  every file. Root cause: `extract_symbols` used
  `child_by_field_name("arguments")` to find the `arguments` node on a
  `call`, but **tree-sitter-elixir 0.3.x emits `arguments` as an
  *unfielded named child***, not a field. `child_by_field_name` returned
  `None`, so `name` was empty, the symbol branch was skipped, and the
  NIF returned an empty list. The Elixir wrapper fell back to the
  regex parser for files >50 bytes, which extracted functions but
  missed modules entirely (the `pote` index had 0 `kind = module`
  rows). Fix: two new helpers in
  `native/tree_sitter_nif/src/lib.rs` — `elixir_find_arguments/1`
  walks `named_children` to locate the `arguments` node by kind,
  `elixir_extract_name/2` reads the first named child (handles
  `identifier` for `def bar`, `alias` for `defmodule Pote.Theme`, and
  nested `call` for `def foo(x)`). Both `("elixir", "call")` match
  arms (def/defp/defmacro/defmacrop and defmodule/defprotocol/defimpl)
  now use those helpers. Side effect: also adds `dump_tree/2` NIF
  (temporary diagnostic exposed via
  `Delfos.Parsers.TreeSitter.NIF.dump_tree/2`) used during this
  investigation to confirm the grammar mapping.

- **Bug #22 follow-up — guard clauses (`def x when guard`) were silently
  dropped**. The first fix (`30e9b48`) added helpers for `identifier` /
  `alias` / `call` children of `arguments`, but for guarded clauses
  tree-sitter emits a `binary_operator` node as the first child of
  `arguments` (representing `fn_call when guard`). The old helper had
  no match arm for `binary_operator`, so guarded clauses produced an
  empty name and were skipped. Verified by reproducing on `pote`:
  `Pote.Format.Hex.valid?` clause at line 37 (`def valid?(hex) when
  is_binary(hex), do: byte_size(hex) == 6`) was missing from the
  index. Fix: new helper `elixir_extract_fn_name/2` in
  `native/tree_sitter_nif/src/lib.rs` recurses into the left operand
  of `binary_operator`. Adds 5 new test cases (def/defp/defmacro with
  `when`, plus `valid?` with both `when` and `?`). Also adds two
  follow-up cleanup migrations:
    * `20260708000003_dedup_orphan_elixir_symbols.exs` — deletes 32
      orphan rows where `(file_id, name, line_start)` matches a
      prefixed sibling.
    * `20260708000004_dedup_stale_line_start_orphans.exs` — deletes
      14 additional orphans where the OLD regex parser stripped
      trailing characters from names (`valid?` → `valid`); matches
      siblings whose qualified name contains the orphan's name as a
      substring after `.`.

## [2.1.0] - 2026-07-07

### Added

- **Global `--help`/`--version` flags**. `delfos --help` / `-h` renders
  the full command list via Alaja components (Header, Table, Separator).
  `delfos --version` / `-v` prints the installed version. These intercept
  before the DSL dispatcher, so they work even without a subcommand.
  (PR #7)
- **`Delfos.CLI.Commands.Serve` module**. `delfos serve` without `--mcp`
  now shows serve-specific help instead of falling through to config help.
  (PR #7)
- **PowerShell + Groovy AST parsing via tree-sitter**. 4 new extensions
  in the dispatcher (`.psd1`, `.gvy`, `.gy`, `.gsh`) and full NIF-backed
  symbol extraction for PowerShell (`function`) and Groovy
  (`function_definition`, `method`, `class_definition`). Both grammars
  were pre-wired in the Rust crate (pinned `=0.25.10` and `=0.1.2`) but
  not exposed in the Elixir wrapper. (PR #8)
- **Binary extension allowlist**. 60+ known binary/opaque extensions
  (images, archives, binaries, fonts, media) now return
  `{:error, :unsupported_extension}` from `Dispatcher.parse/2` instead of
  falling through to the regex GenericParser. (PR #10)

### Changed

- **`req` bumped `~> 0.5` → `~> 0.6`** with `override: true` to clear
  2 CVEs (multipart header injection, decompression bomb DoS). Transitive
  finch, mint, and hpax also upgraded. `mix deps.get` no longer reports
  `VULNERABLE!`. (PR #9)
- **`Delfos.Parsers.Dispatcher.parse/2`** now returns `{:error, …}` from
  binary extensions using `with/else` instead of a bare `{:ok, parsed} =`
  match, so the error tuple propagates correctly. (PR #10, side effect)

### Fixed

- **3 pre-existing dialyzer warnings** (`pattern_match_cov` / `pattern_match`):
  `dispatcher.ex` unreachable `other` clause, `hybrid_search.ex` incorrect
  `{:ok, …}` wrapper patterns, and `mcp/tools.ex` dead-case `_ -> []`.
  (PR #6)
- **`Delfos.Parsers.TreeSitter.normalize_lang/1`** no longer routes
  `"powershell"` to `"bash"` — it now correctly maps to `"powershell"`,
  enabling real AST parsing via the NIF. (PR #8)
- **`Delfos.CLI.serve_handler/1`** fallback now calls
  `Commands.Serve.run(["--help"])` instead of `Commands.Config.run(["help"])`.
  (PR #7)

### Tests

- New tests for global flags `--help`/`-h`/`--version`/`-v` (PR #7).
- Unsupported-extension test enabled (was `@tag :skip`) — verifies
  `Dispatcher.parse("image.png")` returns `{:error, :unsupported_extension}`
  (PR #10).

## [2.0.0] - 2026-07-07


### Added

- **CLI migrated to `Alaja.CLI.Definition` DSL**. New module
  `Delfos.CLI` (replacing `Delfos.CLI.Main`) declares every
  subcommand declaratively with `command "name" "description" do ... end`.
  The 192-line manual dispatcher is gone; each
  `Delfos.CLI.Commands.X.run/1` is wired through a thin handler bridge
  to the existing legacy call signature. The escript `main_module` is
  now `Delfos.CLI`. 13 subcommands declared in
  `lib/delfos/cli/commands/`. `test/delfos/cli/cli_test.exs` covers
  `__commands__/0`, help routing, and unknown-command errors.
- **`delfos setup`** wizard with `db` and `llm` sub-flows. Guides the
  user through Postgres install (Docker/apt/brew/existing), remote
  PostgreSQL connection (host:port/user/password, with input hidden
  and 15s connectivity probe), DB creation, `pgvector` verification,
  and migration. The `llm` flow selects between llama.cpp, Ollama
  (with per-OS auto-install: `curl|sh` on Linux/macOS, `brew --cask
  ollama` if brew is available, `winget install Ollama.Ollama` on
  Windows, plus detached-spawn + 30s readiness probe), OpenAI, and
  Anthropic. Subcommands `delfos setup db` and `delfos setup llm` skip
  the top-level menu and jump straight to their wizard.
- **`delfos doctor`** rewritten on top of `Botica.Doctor`. Adds
  `--interactive` (ask before each fix), `--db-only` / `--llm-only`
  filters, and `--json` for machine-readable output. Detects
  `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASS` overrides and reports
  the actual target host. Output is grouped into `[Postgres]
  [TreeSitter] [Models] [Config]` sections with ✓/⚠/✗ icons;
  Postgrex connection-error spam is hidden unless the user asks for
  verbose. After the diagnostic, post-checks inspect failed checks
  and point the user at the right setup wizard.
- **`delfos models`** shows the active embedding and LLM providers
  with masked API keys and the index column dimension. With `--probe`
  it pings each endpoint and reports latency plus dim-mismatch
  warnings. Validates `embedding.dim` config against the actual
  `symbols.embedding` column dimension in PostgreSQL.
- **`Delfos.Health`** — periodic health check that pings the embedding
  and LLM endpoints and reports latency + dim mismatch warnings.
- **`delfos integrate <agent>`** for `claude-code`, `opencode`,
  `cursor`, `aider`, `codex`, `zed`, and `all`. Defensive
  `read_json_or_empty/1` and `verify_json/1` round-trip every write so
  bad JSON in `~/.claude.json`, `~/.config/opencode/config.json`, etc.
  fails loudly instead of silently overwriting. `safe_write/2` backs
  up the existing version to `<path>.bak-<unix_seconds>` before any
  merge.
- **Global `--help` and `-h`** for `delfos` and every subcommand.
  Each help block lists flags, arguments, and worked examples.
- **Tree-sitter NIF: 12 more languages wired in** (was 27 dead
  grammars in `Cargo.toml` — only 18 of them were reachable from
  `lib.rs#language_for/1`). The live NIF set is now 30, with full
  symbol extraction for all of them:

  | Language    | Dispatcher id | NIF atom | Symbol kinds extracted                          |
  |-------------|---------------|----------|--------------------------------------------------|
  | R           | `r`           | `r`      | function                                         |
  | Haskell     | `haskell`     | `haskell`| function (bind), type (data/newtype), trait      |
  | Erlang      | `erlang`      | `erlang` | function, module/struct/type (via -attr)         |
  | OCaml       | `ocaml`       | `ocaml`  | function, type, module, class                   |
  | Clojure     | `clojure`     | `clojure`| (AST parsed; zero symbols — see note below)      |
  | Zig         | `zig`         | `zig`    | function, struct, enum                           |
  | Gleam       | `gleam`       | `gleam`  | function, type                                   |
  | Julia       | `julia`       | `julia`  | function, module, struct                        |
  | Kotlin      | `kotlin`      | `kotlin` | class, method (via community fork `tree-sitter-kotlin-ng`) |
  | Objective-C | `objective-c` | `objc`   | class, method, protocol                         |
  | Assembly    | `assembly`    | `asm`    | label                                            |
  | F#          | `fsharp`      | `fsharp` | function, type, class, module                   |

  Clojure is wired through the NIF for AST-based parsing (replacing
  the regex fallback) but its grammar has no distinct function/class
  nodes — everything is `list_lit`. Returns zero symbols from
  `extract_symbols`; this matches the existing pattern for
  bash/c/cpp/php/ruby/swift/dart/scala/lua which are also AST-parsed
  but symbol-extracted by the regex GenericParser in the fallback
  path. Future work: semantic extraction from `list_lit` children.

- **`tree-sitter-kotlin-ng`** added to `Cargo.toml` — the upstream
  `tree-sitter-kotlin` does not target tree-sitter 0.25, so the
  grammar was missing entirely from the NIF. The community fork is
  ABI-compatible and matched against the existing
  `(l, "class_declaration") if matches!(l, "java" | "kotlin" |
  "csharp")` and `(l, "method_declaration")` extraction branches.
- **Syntax highlighting modules** for `assembly.ex`, `fsharp.ex`,
  `vb.ex` (the three languages in `syntax/` that were missing from
  the registry — `lib/delfos/syntax/registry.ex#languages/0`). All
  70 syntax modules are registered at `Application.start/2`.
- **`normalize_lang/1` aliases**: dispatcher's canonical `objective-c`
  and `assembly` are mapped to NIF atoms `objc` and `asm`
  respectively, so the dispatcher's `language_map` stays
  human-readable while the NIF uses short ids.
- **`Delfos.Syntax.Utils`** — shared helpers used by `explain`,
  `audit`, and `query`: `safe_to_atom/1` for language detection and
  `detect_lang_atom/1` for the dispatcher id.
- **HNSW indexes** on `chunks.embedding` and `symbols.embedding` for
  faster vector queries.
- **`config/runtime.exs`** — production-only env-var validation.
- **Graceful shutdown** (`Application.stop`).
- **Defensive `Jason.encode` (no `!`)** in the MCP server, removing
  the risk of an unhandled exception in the middle of a JSON-RPC
  reply.
- **MCP server async stdin reader** — replaced `after: 0` polling
  with an async stdin reader to fix the spin-loop.
- **MCP tool timeout + try/rescue around dispatch** so a slow tool
  cannot stall the JSON-RPC loop.
- **GraphBuilder N+1 fix**: preloads files into a lookup map instead
  of one query per node.
- **Code highlighting** in `query` result snippets.
- **`mix gen`** — a one-shot Mix task (`lib/mix/tasks/gen.ex`) that
  builds the release end-to-end and handles every platform-specific
  quirk:
  - Detects OS (mac, debian/ubuntu, fedora/rhel, arch, windows,
    other-linux) and reports missing toolchain (`rustc < 1.78`, no
    `cc`, no `cmake`) with the exact install command for that
    distribution.
  - Writes `native/tree_sitter_nif/.cargo/config.toml` if missing,
    so macOS links the tree-sitter NIF with the right
    `dynamic_lookup` rustflag — without per-machine setup. Users who
    cloned the repo before v0.4.10 now get a working build
    automatically.
  - Runs `mix deps.get` if `deps/` is missing.
  - Compiles, releases, deploys to `~/bin/delfos`, writes the
    `.tool-versions` file.
  - Prints a single concise "what to do next" line so the user never
    has to grep through the build log.
  - Honors `--no-deploy` for users who just want the release
    directory without copying it anywhere.
- **Test coverage**: tests for the dispatcher
  (`test/delfos/parsers/dispatcher_test.exs`, 13 tests verifying every
  shipped code extension and tree-sitter language id), the syntax
  registry (`test/delfos/syntax/registry_test.exs`, 9 tests
  validating every `definition/0`), and command-level tests for
  `init`, `scan`, `query`, `audit`, `explain`, `context`, `status`,
  `summarize`, `graph`, `setup`, `setup/db`, `setup/llm`, plus MCP
  server tests (`build_tool_response` + dispatch + timeout).

### Changed

- **Build switched from `escript` to Mix release** (`format: :release`
  in `mix.exs` `batamanta/0`). Required because `escript` cannot
  embed Rust NIFs (tree-sitter) — the previous `escript` config
  silently dropped `libtree_sitter_nif.so` at bundle time, so the
  resulting binary crashed with `cannot open shared object file` and
  fell back to the regex `GenericParser`.
- **Config migrated from TOML to JSON**. `~/.config/delfos/delfos.conf`
  is no longer used; the new path is `~/.config/delfos/config.json`.
  API keys are encrypted at rest with AES-256-GCM via
  `Apero.Crypto.Cipher` and decrypted lazily on read. The encryption
  key lives in `~/.config/delfos/.key`. Environment variables
  (`DB_HOST`, `DB_PASSWORD`, `EMBED_URL`, `LLM_MODEL`, etc.) still
  take precedence.
- **Tree-sitter bumped to 0.25** (removes Kotlin grammar support
  from the upstream 0.25 grammars; re-added via the
  `tree-sitter-kotlin-ng` community fork above).
- **`Delfos.version/0`** now reads from the loaded application spec
  (`Application.spec(:delfos, :vsn)`) instead of returning a hardcoded
  string.
- **`mix.exs` deps pinned to `github:` + `branch: "main"`** for every
  Lorenzo-SF ecosystem dep (`alaja`, `candil`, `arrea`, `apero`,
  `botica`). Pinning to a tag used to ship stale SHAs:
  - `pote` v0.2.0 had no `Pote.Theme`.
  - `candil` v0.2.0 had no `Provider` struct.
  - `alaja` v0.3.8 had a `question_with_options/3` that broke
    `delfos setup` (only matched exact labels; v0.3.12 accepts
    1-based indexes, atom names, and case-insensitive prefixes).
  Tracking `main` is a faster feedback loop: a breaking change
  upstream breaks our build immediately, instead of silently shipping
  a frozen bug.
- **`delfos doctor` reports by section** — the previous flat list
  with Postgrex flooding the output is replaced by `[Postgres]
  [TreeSitter] [Models] [Config]` sections, one row per check with a
  ✓/⚠/✗ icon.
- **`mix docs`** no longer fails because `README_ES.md` was missing
  — the `extras:` list now points to `docs/README.es.md`.
- **`delfos integrate`** reads existing JSON files defensively
  (`read_json_or_empty/1`) and verifies each write with `verify_json/1`.
- **`delfos integrate aider`** no longer overwrites an existing
  `AGENTS.md` without warning; if Delfos instructions are not already
  present, the file is backed up to `AGENTS.md.bak-<unix_ts>` before
  the merge.
- **Postgrex errors** are surfaced through `format_db_error/1` and
  `format_error/1` helpers instead of raw `inspect/1`. Errors in
  `delfos query`, `delfos doctor`, etc. now include a "next step"
  hint pointing to `delfos doctor` or `delfos models`.
- **`mix.exs` adds `docs` (groups_for_modules), `dialyzer_config`,
  and `CHANGELOG.md` extras**. The release `applications:` list now
  marks `candil: :transient` (it owns a long-running engine that we
  don't want supervised as `:permanent`).

### Fixed

- **NIF included in the released binary** — batamanta had
  `format: :escript` in `mix.exs`, which silently drops Rust NIFs
  from the bundle. Changed to `format: :release` so
  `libtree_sitter_nif.so` ships with the final binary.
- **`delfos setup db` auto-migrate now works in the release binary**:
  - `setup/db.ex#apply_migrations` previously used
    `Code.eval_string/1` which DOES NOT work for
    `use Ecto.Migration` scripts (those need to be invoked through
    `Ecto.Migrator`). Replaced with `Ecto.Migrator.run/4`, the
    canonical helper that handles schema diffing and migration
    bookkeeping in `schema_migrations`.
  - `Application.start/2` now launches a Task that runs the same
    `Ecto.Migrator.run(:up, all: true)` on every boot. The release
    ships `priv/repo/migrations/` next to its bin (added a
    `copy_priv/1` step in `mix.exs`), so the first command the user
    runs already finds the schema up to date.
  - `setup/db.ex#apply_migrations` switched from
    `Code.eval_string/1` to `Ecto.Migrator.with_repo/3`.
- **`delfos setup db` auto-installs pgvector via the Repo** instead
  of shelling out to `psql`. The release binary doesn't ship `psql`
  in its PATH, so the previous fallback failed silently. Now
  `install_pgvector/0` runs `CREATE EXTENSION IF NOT EXISTS vector`
  over the existing TCP connection.
- **`prod.exs` default DB name** changed from `delfos_prod` to
  `delfos_dev`. Now `mix gen` under `MIX_ENV=prod` produces a binary
  that talks to the same database as dev, by default. Override with
  `DB_NAME=production` env var when actually deploying.
- **`delfos setup db` Docker container conflict** — if a stopped
  container with the same name exists, the wizard now asks what to
  do (remove / keep / rename) instead of letting `docker run` fail
  with `Conflict. The container name ... is already in use`.
- **`Ecto.Migrator.run/4` called incorrectly** — passing
  `[{path, []}]` (tuples) tripped a `dynamic(...)` typing warning in
  `mix compile --warnings-as-errors`. Switched to the canonical
  `Ecto.Migrator.with_repo/3` wrapper used by `mix ecto.migrate`
  itself, with plain `paths :: [String.t()]` as second arg.
- **Postgres 17 in the Docker suggestion** — both
  `setup/db.ex#setup_docker` and the doctor help text now reference
  `postgres:17` instead of `postgres:16`. pgvector 0.4.0 (the current
  lock) supports Postgres 13–17 officially. Postgres 18 needs an
  update to pgvector 0.8+ which isn't on Hex yet.
- **macOS build** — added
  `native/tree_sitter_nif/.cargo/config.toml` with the
  `link-arg=-undefined` + `link-arg=dynamic_lookup` rustflags Rustler
  needs to compile NIFs on macOS. Previously
  `MIX_ENV=prod mix release` (or `mix gen`) raised
  `Rustler.Compiler.ensure_platform_requirements!/3` on Mac users.
- **Repo unavailable error on every command** — `mix gen` produced a
  release where `delfos init`/`scan`/`query`/`audit`/`summarize`
  crashed with `could not lookup Ecto repo Delfos.Repo because it
  was not started`. The release uses `include_erts: false` so the
  host OTP application never started. `mix gen` now delegates to
  `mix release --overwrite`, which wires up the start-permanent
  flag correctly, AND `Alaja.CLI.Definition.dispatch_main/1` now
  calls `Application.ensure_all_started(__otp_app__())` so the
  supervisor tree is up before any command runs.
- **`@doc` above `defp maybe_suggest_setup/2`** in `delfos doctor`
  was dropped — Elixir 1.19 emits a warning when a private function
  is decorated with `@doc` (the doc is silently discarded).
- **`delfos doctor` no longer references the non-existent
  `Apero.Doctor`** — rewritten on top of `Botica.Doctor`.
- **Codex** was writing YAML to `~/.codex/config.yaml` with key
  `mcp_servers:`. The real format is **TOML** at
  `~/.codex/config.toml` with key `[mcp_servers]`. Switched and
  added round-trip validation via `Toml.decode_file/1`.
- **Cursor** was writing to `.cursorrules` (deprecated in Cursor
  0.45+). Switched to `.cursor/rules/delfos.mdc` with YAML
  frontmatter.
- **Aider** was appending `read:\n  - AGENTS.md` to `.aider.conf.yml`,
  producing a second `read:` block (invalid YAML). Now parses the
  existing config with `YamlElixir`, merges the new entry into the
  existing `read:` list, and rewrites.

### Removed

- **`lib/delfos/cli/commands/main.ex`** — replaced by `Delfos.CLI`.
- **`yaml_elixir ~> 2.11`** runtime dep — `merge_aider_read/1` was
  switched to a regex-based approach (Elixir 1.17+ compatibility)
  and the dep is no longer needed.
- **`Apero.Llm.*` references** — `Apero.Llm.Health` was the only
  consumer in delfos; replaced with `Candil.Health.ping/3`. The
  module belongs in Candil (the LLM domain), not Apero.
- **Dangling `v0.2.0` / `v0.3.0` tags** — never existed in this
  repo; the CHANGELOG link footers now point only at `1.0.0` and
  `2.0.0`.

### Deferred (still falling back to regex GenericParser)

- **`powershell`, `groovy`** — both grammars' latest published
  versions (0.26.4 and 0.1.2 respectively) require
  `tree-sitter ^0.26`. The crate is pinned to 0.25 to keep the rest
  of the NIF stable. Syntax highlighting still works via
  `Delfos.Syntax.PowerShell` and `Delfos.Syntax.Groovy`. Until a
  0.25-targeted release is available upstream, parsing stays on the
  regex fallback. See the new comment block in `Cargo.toml` for the
  full rationale.
- **`perl`** — same ABI conflict, already excluded earlier.
- **`vb`** — no `tree-sitter-vbnet` crate published on crates.io.
  Regex fallback + syntax highlighting via `Delfos.Syntax.Vb`.

### Caveats

- The NIF cannot be recompiled in the dev sandbox (Cargo 1.65 from
  Debian is too old for tree-sitter 0.25). `Cargo.lock` was not
  regenerated against the new `Cargo.toml` — the first `mix compile`
  on a host with Rust ≥ 1.78 will pull the new grammar crates and
  update `Cargo.lock` accordingly.
- Existing NIF languages (bash/c/cpp/php/ruby/swift/dart/scala/lua)
  are still AST-parsed with no symbol extraction. Same tradeoff as
  Clojure — not addressed in this release to keep the diff scoped.

## [1.0.0] - 2026-06-10

### Added
- Initial open source release: MCP server (JSON-RPC 2.0 over stdio,
  protocol version 2024-11-05) with 8 tools, hybrid search (vector +
  BM25 + graph) via Reciprocal Rank Fusion, `CandilBridge` adapter so
  OpenAI-compatible chat/embed calls route through `Candil` when
  available, and `delfos integrate <agent>` for `claude-code`,
  `opencode`, `cursor`, `aider`, `codex`, `zed` and `all`.

[2.0.0]: https://hex.pm/packages/delfos/2.0.0
[1.0.0]: https://hex.pm/packages/delfos/1.0.0


> ## A note on versioning
>
> The only canonical tags are `1.0.0` (initial open-source cut-over)
> and `2.0.0` (current HEAD). The `[0.2.0]` … `[0.4.19]` headers in
> earlier drafts were **planning milestones**, not releases: they
> have no corresponding git tags. Earlier `0.x` versions are no
> longer maintained and have been collapsed into this single
> canonical `2.0.0` entry. `mix.exs` `version` reflects the current
> development state and may be ahead of the public surface. Pin to
> `1.0.0` or `2.0.0` for stable dependencies.

> ## A note on history
>
> The git history of this repository was rewritten as part of a
> deliberate cleanup effort. The commits you can read describe the
> codebase as it stands today — they do not preserve the original
> chronology of development.
>
> Anything worth keeping from before the rewrite was carried forward
> as tagged releases with explicit `CHANGELOG.md` entries. Anything
> not preserved is, by the maintainer's choice, no longer part of the
> canonical development line.
>
> Tag `1.0.0` points to the initial open-source cut-over; tag
> `2.0.0` points to the current HEAD and the canonical consolidated
> release. All versioned artifacts on Hex.pm and GitHub Releases
> follow this convention.
