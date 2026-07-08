# Delfos — Estado actual de la sesión (single source of truth)

> **Status**: in progress
> **Last update**: 2026-07-08 (after re-test round)
> **Goal**: This document captures WHERE WE ARE so a future session can
> pick up the work without losing context.

---

## TL;DR

- **Binary**: `~/bin/delfos` v2.2.0 (rebuilt with `mix gen` from `~/cacafuti/delfos/`)
- **44 commits ahead of origin/main** (NOT pushed — user pushes manually)
- **Tags in sync**: `2.0.0` (044d40c), `2.0.1` (8938eb2), `2.1.0` (2fe40da), `2.2.0` (aa58986)
- **Test project for MCP**: `~/cacafuti/pote` (91 files, 269 symbols, 100% embedded, 53 chunks)
- **Opencode**: configured with delfos MCP at `~/.config/opencode/opencode.json`
- **LLMs**: auto-start via `~/bin/llama-run` (Delfos now uses llama-run if available)

---

## What's fixed

### All 25+ bugs from E2E test + opencode session (committed)
All bugs #1-26 (except #22 NIF, #25 arch limitation) are fixed in 42 commits.

### Latest changes (not yet committed — from this session)

1. **MCP tool dispatch — fallback names** (`server.ex`):
   - Added `normalize_tool_name/1` that handles:
     - Double prefix (`delfos_delfos_search` → `delfos_search`)
     - Short names (`search`, `symbol`, `files`, etc.)
   - Tested: `search`, `files`, `symbol` all work via MCP
   - Fixes the "Herramienta desconocida" error when opencode strips prefixes

2. **LLM auto-start & health check** (`llm_discovery.ex`):
   - **Deep HTTP health check**: now sends `GET /health` (not just TCP port check). Catches processes listening but not serving (e.g. stalled model load).
   - **Auto-start via llama-run**: `start_llama_server` now detects `~/bin/llama-run` and uses it to start the right model (`embed` / `gpt-oss`). Falls back to raw `llama-server` if wrapper not found.
   - **Model info in endpoint status**: stores `:model` key so start commands know which model to load.
   - **Better error messages**: shows role, URL, and model name when reporting failures.

---

## Open issues

### Bug #22 (NIF) — tree-sitter doesn't extract `defmodule` / `defmacro`
- Full briefing: `docs/NIF_TREE_SITTER_MODULE_FIX.md`
- 0 modules in DB despite 170+ in source
- Not fixed — requires Rust NIF change (big task)

### Bug #25 — callers/callees empty for metaprogrammed functions
- `Pote.Theme.resolver/1` called from `__using__` macro but relationships table has 0 edges
- Fundamental architecture limitation (mix xref + regex don't see `quote do` blocks)
- Documented, not fixable without NIF change

### `delfos_files` shows "Unknown" in opencode
- Suspected opencode client-side prefix stripping issue
- Delfos MCP server now accepts all 3 name variants (`delfos_files`, `files`, `delfos_delfos_files`)
- The "Unknown" display is likely opencode's rendering, not a Delfos error

### Search with broad Spanish terms returns no results
- Semantic search (Qwen3-Embedding-8B, 4096-dim) doesn't match Spanish queries to English code
- Expected behavior: use English terms or exact symbol names

---

## Re-test results (this session)

| Test | Prompt | Result |
|------|--------|--------|
| T1 | List MCP tools | ✅ PASS (same as before) |
| T2 | Search config_app + symbol | ✅ PASS (UNEXTRACTED flag works, model reads source as fallback) |
| T3 | Find main config function + graph | ✅ PASS (model identified `put_theme_resolver/1`, reconstructed graph manually) |

## Latest build
```bash
cd ~/cacafuti/delfos && mix gen && cp ./delfos ~/bin/delfos
# Binary: /home/merendandum/bin/delfos (ELF 64-bit, 100MB)
```

## Latest changes — Bug #22 fix (this session, after 44-commit push)

### Bug #22 — NIF tree-sitter-elixir returned 0 symbols (FIXED)

**Root cause confirmed**: `extract_symbols` in
`native/tree_sitter_nif/src/lib.rs` used
`child_by_field_name("arguments")` to find the `arguments` node on Elixir
`call` nodes. But **tree-sitter-elixir 0.3.x emits `arguments` as an
unfielded named child** of `call`, not a field. So `child_by_field_name`
returned `None`, the symbol's `name` was empty, the `if !name.is_empty()`
branch was skipped, and the NIF returned `[]`. The Elixir wrapper's
fallback safety net (regex parser for files >50 bytes) caught the
functions but missed `defmodule` entirely → 0 `kind=module` rows in the
index.

**Fix** (`native/tree_sitter_nif/src/lib.rs` +52 / -11):
- `elixir_find_arguments/1` — walks `node.named_children()` to locate
  the `arguments` node by kind (no field lookup).
- `elixir_extract_name/2` — reads first named child of `arguments`,
  handling `identifier` (bare `def bar`), `alias` (`defmodule Pote.Theme`),
  and nested `call` (parenthesized `def foo(x)`).
- Both `("elixir", "call")` arms now use these helpers.

**Verification** on `~/cacafuti/pote`:
- Before fix: 0 modules, all function `qualified_name == name` (no prefix).
- After re-scan with fixed NIF: **41 modules**, **119 symbols with
  proper `Module.fn` qualified names**, total 341 symbols (up from 269).
- File-level sample — `lib/pote/format/hex.ex` now has symbols like
  `Pote.Format.Hex.parse`, `Pote.Format.Hex.valid?`,
  `Pote.Format.Hex.normalize_hex`.

**Caveats** (next steps for cleanup, not blockers):
1. 48/91 files in `pote` timed out on embeddings during the re-scan
   (Qwen3-Embedding-8B degradation after prolonged CPU use, per session
   notes). Those files keep their stale pre-fix symbols. Restarting
   the embed server unblocks them — `~/bin/llama-run embed stop &&
   ~/bin/llama-run embed start` then re-run `delfos scan --full`.
2. Pre-existing symbols with `qualified_name = "x"` and `line_start=0`
   remain alongside new prefixed ones, causing some duplicates. The
   `upsert_symbol` lookup uses `(name, line_start)`; when line_start
   differed between pre-fix and post-fix parsing, both rows survive.
   For a clean slate: `DELETE FROM symbols` + `DELETE FROM files`
   + `DELETE FROM chunks` + `DELETE FROM edges` + re-run `init`. Or
   hand-write a SQL that keeps only rows whose `qualified_name =
   name OR qualified_name LIKE '%.name'`.

### Diagnostic NIF kept

`dump_tree/2` is exposed via
`Delfos.Parsers.TreeSitter.NIF.dump_tree/2` (Rust impl + Elixir stub).
Use it to inspect raw grammar output:
```elixir
NIF.dump_tree("elixir", "defmodule Foo do\n  def bar, do: :ok\nend")
```
Lives in `native/tree_sitter_nif/src/lib.rs` lines 838-869. Useful for
future grammar debugging. Keep or remove in a follow-up commit.

---

## Open / follow-up tickets

### Ticket A — Embed server restart + re-scan pote
**Priority**: medium. **Complexity**: low.
- `~/bin/llama-run embed stop && ~/bin/llama-run embed start`
- `~/bin/delfos scan --full --workers 4`
- Expected: all 91 files indexed, duplicate fix above eliminates
  stale rows.

### Ticket B — DB cleanup for stale symbols
**Priority**: low. **Complexity**: low.
- One-time migration or manual SQL. See "Caveats #2" above.
- Alternative: drop `symbols`/`files`/`chunks`/`edges` and
  `~/bin/delfos init /home/merendandum/cacafuti/pote` to start fresh.

### Ticket C — Git LFS for `*.so` files
**Priority**: low. **Complexity**: high. **Status**: deferred.
- GitHub warns the 65 MB `libtree_sitter_nif.so` exceeds 50 MB.
- Either `git lfs track "*.so"` + migrate, or stop shipping the .so
  in the repo and let `mix gen` build it from source on `mix deps.get`.

### Ticket D — Decide if `dump_tree` stays public
**Priority**: low. **Complexity**: trivial.
- Either remove (cleaner release binary) or document it as a
  debugging aid (`docs/debugging.md`).


## Final state — Ticket A complete (this turn)

After re-scan with the new NIF (fix #2 — guard clauses) and the two
cleanup migrations applied:

| Metric | pre-Bug-22 | post-fix | post-scan |
|---|---|---|---|
| Symbols | 269 | 318 (after dedup) | **344** |
| Modules | 0 | 43 | **44** |
| Functions with proper `qn` | 0 | 137 | **179** |
| Top-level functions (legit) | 269 | 123 | 120 |
| Macros | 0 | 1 | 1 |
| Files w/o symbols | 91 (all broken) | 47 | **46** |

The 46 remaining files without symbols are:
- **45 JSON test fixtures** in `tmp/Pote.ThemeTest/...` (data files, not Elixir source — `tmp/` now in ignore_dirs but these rows predate the fix and weren't cleaned up).
- **`test_helper.exs`** — contains only `ExUnit.start()`, no `def`/`defmodule`. Legitimately has zero symbols.

Scan time on `pote`: ~21 min (1260s) for the 46 changed files with workers=1.
Embed server state: healthy at end (12h 57m CPU time, well past the
"~198 min" degradation threshold noted earlier — still responsive, 9s
per batch of 48).

### Verification commands
```bash
~/bin/delfos status
# Should show: Files: 91 / Symbols: 344 / 100.0% embedded

PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -d delfos_prod -c "
  SELECT s.kind, COUNT(*),
    COUNT(*) FILTER (WHERE s.name = s.qualified_name) AS unprefixed,
    COUNT(*) FILTER (WHERE s.name != s.qualified_name) AS prefixed
  FROM symbols s JOIN projects p ON p.id=s.project_id 
  WHERE p.name='pote'
  GROUP BY s.kind ORDER BY 2 DESC;"
# Result:
#   function | 299 | 120 (top-level) | 179 (in module)
#   module   |  44 |  44              |   0
#   macro    |   1 |   0              |   1
```

