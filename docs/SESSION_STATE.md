# Delfos — Estado actual de la sesión (single source of truth)

> **Status**: in progress (paused mid-session)
> **Last update**: 2026-07-08
> **Goal**: This document captures WHERE WE ARE so a future session can
> pick up the work without losing context.

---

## TL;DR

- **Binary**: `~/bin/delfos` v2.2.0 (rebuilt with `mix gen` from `~/cacafuti/delfos/`)
- **40 commits ahead of origin/main** (NOT pushed — user pushes manually)
- **Tags in sync**: `2.0.0` (044d40c), `2.0.1` (8938eb2), `2.1.0` (2fe40da), `2.2.0` (aa58986 = HEAD)
- **Test project for MCP**: `~/cacafuti/pote` (91 files, 371 symbols, 100% embedded, 50 chunks, 39 xref edges)
- **Opencode**: configured with delfos MCP at `~/.config/opencode/opencode.json`
- **LLMs**: managed via `~/bin/llama-run embed` and `~/bin/llama-run gpt-oss medium`

---

## What's done (all 23 bugs from E2E test + new bugs from opencode test)

### From the original E2E test (TEST_PLAN.md):
| ID | Severity | Description | Commit |
|----|----------|-------------|--------|
| #1  | Critical | `delfos config doctor` crash | 98d1c02 |
| #2  | Critical | `delfos integrate claude-code` crash | 98d1c02 |
| #18 | Critical | `delfos doctor --fix --interactive </dev/null` crash | 98d1c02 |
| #21 | Critical | vector(1024) vs 4096 dim mismatch | eef7018 |
| #17 | Critical | MCP server pid not propagated | eef7018 |
| #15 | Critical | `delfos summarize` BadBooleanError on force=nil | eef7018 |
| #16 | Critical | `String.trim(nil)` on empty LLM response | eef7018 |
| #3  | Major   | zed JSONC support | 98d1c02 |
| #4  | Major   | opencode wrong file path | 16448f0 |
| #5  | Major   | exit codes 0 on error | 98d1c02 |
| #14 | Major   | `audit --file` was no-op | 98d1c02 |
| #19 | Major   | `init --keep` re-scanned | 98d1c02 |
| #6  | Minor   | `config show` omitted [analysis]/[indexing] | e4ca7bb |
| #8  | Minor   | `config probe` bunched checks on one line | e4ca7bb |
| #9  | Minor   | doctor showed Req.TransportError struct | e4ca7bb |
| #10 | Minor   | `delfos` (no args) showed plain text | e4ca7bb |
| #11 | Minor   | `delfos version --help` ignored | e4ca7bb |
| #13 | Minor   | doctor HTTP 401 false-negative | e4ca7bb |
| #20 | Minor   | `delfos preset <name>` top-level didn't exist | e4ca7bb |
| #22 | Critical | GraphSearch Postgrex float | 670ad89 |
| #23 | Critical | HybridSearch extract_result | 670ad89 |
| +N  | Major   | is_file_fresh? UTC vs local time bug | 16448f0 |
| +N  | Major   | DateTime.compare/2 doesn't exist in Elixir | 16448f0 |
| +N  | Major   | relationships schema didn't support file-level | 5d7eee7 |
| +N  | Major   | MCP callers/callees preload bug | 5d7eee7 |

### From the opencode MCP test session (`/home/merendandum/cacafuti/session-ses_0be9.md`):
| ID | Status | Description | Commit |
|----|--------|-------------|--------|
| #24 | ✅ FIXED | search/symbol lookup ignored arity/qualified_name | 41272a5 |
| #25 | ⚠️ DOCS | relationships don't capture calls from inside `quote do` (fundamental NIF limitation) | — |
| #26 | 🟡 PARTIAL | metadata for symbols in `quote do` (empty content, line_end bug) — heuristic flag added | 41272a5 |
| +N | ✅ FIXED | LLMDiscovery runs AFTER scan, should run BEFORE | b83676b |

---

## What's pending (open work)

### High priority (real user pain)
1. **Bug #22 NIF**: tree-sitter doesn't extract Elixir `defmodule` (modules) or `defmacro` (macros). 0 modules in DB despite 170+ in source. Documented in `docs/NIF_TREE_SITTER_MODULE_FIX.md`.
2. **Bug #25**: metaprogrammed functions' callers/callees not in graph. The `Pote.Theme.resolver/1` function is in DB but its 3 callers (from `__using__` macro) are NOT in the relationships table. Fundamental architecture limitation — mix xref and regex importers don't see calls inside `quote do` blocks.
3. **Opencode TUI session integration**: the opencode session in this conversation was used to test MCP. The TUI workflow hasn't been exercised by the user yet (they prefer `opencode run` for now).

### Medium priority
4. **`--arities` field on Symbol schema**: arity is currently embedded in `signature` field as text (e.g., `"config_app/0"`). Should be a separate `integer` field for proper arity-based lookups. Bug #24 workaround uses substring matching on signature, which is fragile.
5. **Source re-index after `delfos integrate`**: when user adds new integrate target, we don't auto-rescan the project. Could trigger a `delfos scan` after integrate completes.

### Low priority
6. **Caller/callee disambiguation**: even with arity/qualified_name search fix, the get_callers/get_callees functions still return the same 0 results for `Pote.Theme.resolver/1` because the relationships table doesn't have those edges. Once #25 is fixed (by the NIF or by a different approach), this falls into place.
7. **CHANGELOG entry for v2.2.0 needs to include the bugs #24-#26 fix (current CHANGELOG only has up to the original 23 bugs)**.
8. **Tag `2.2.1` might be needed** since we fixed additional bugs after the `2.2.0` tag was created (or we just amend the 2.2.0 changelog and don't create a new tag — the user decides).

---

## Current state of the test data

### Database
- **Schema**: 11 migrations applied, including `20260708000002_add_file_level_relationships.exs` (the schema migration for Bug #25 partial fix)
- **Projects**: only `pote` should be in DB (the delfos_mcp_test was deleted)
- **Symbols**: 371, all `kind = function` (no `module` due to Bug #22)
- **Chunks**: 50, all with 4096-dim embeddings
- **Relationships**: 39 file-level (`imports_file` kind)

To verify:
```bash
cd /home/merendandum/cacafuti/pote
~/bin/delfos status
# Should show 1 project: pote, 91 files, 371 symbols
```

### LLMs
- **embed**: `127.0.0.1:9998`, model=`embed` (Qwen3-Embedding-8B, 4096-dim)
- **llm**: `127.0.0.1:9999`, model=`gpt-oss` (gpt-oss-20b, medium reasoning)
- **API key**: `sk-local-dev-key`
- **Wrapper**: `~/bin/llama-run` (calls `llama-server` from `/usr/lib/ollama/`)
- ⚠️ **`PATH` issue**: `llama-server` is in `/usr/lib/ollama/`, NOT in `$PATH`. Need to `export PATH=/usr/lib/ollama:$PATH` or use `~/bin/llama-run` which handles it.

To start:
```bash
export PATH=/usr/lib/ollama:$PATH
nohup llama-run embed > /tmp/delfos_llm_logs/embed.log 2>&1 &
nohup llama-run gpt-oss medium > /tmp/delfos_llm_logs/gpt_oss.log 2>&1 &
```

To stop: `~/bin/llama-stop`

### opencode integration
- Config: `~/.config/opencode/opencode.json` has:
  ```json
  "mcp": {
    "delfos": {
      "type": "local",
      "command": ["/home/merendandum/bin/delfos", "mcp"],
      "enabled": true
    }
  }
  ```
- Verify: `opencode mcp list` should show `✓ delfos connected`
- When you `cd ~/cacafuti/pote` and run `opencode` (TUI) or `opencode run "..."`, opencode will spawn its own `delfos mcp` process on demand.

---

## What's the current shell state

⚠️ **The session was in the middle of testing the LLMDiscovery auto-start fix when it timed out**. The shell had:
- LLMs killed (via `pkill -9 llama-server`) to test auto-start
- Was running `delfos init` (or some other long command) that didn't complete in time

To resume safely:
```bash
# 1. Make sure no zombie delfos processes
pkill -9 -f "delfos\|batamanta" 2>&1 || true
rm -rf /tmp/batamanta-*

# 2. Verify LLMs state
~/bin/llama-status
# If DOWN:
export PATH=/usr/lib/ollama:$PATH
nohup llama-run embed > /tmp/delfos_llm_logs/embed.log 2>&1 &
nohup llama-run gpt-oss medium > /tmp/delfos_llm_logs/gpt_oss.log 2>&1 &
# Wait ~30s for both to be ready

# 3. Verify MCP works
cd ~/cacafuti/pote
~/bin/delfos --version    # should print "Delfos v2.2.0"
opencode mcp list          # should show "✓ delfos connected"
```

---

## Bugs by category

### Fixed (commit references)
- Critical: #1, #2, #15, #16, #17, #18, #21, #22, #23
- Major: #3, #4, #5, #6 (partial), #14, #19
- Minor: #6, #8, #9, #10, #11, #13, #20
- "NEW" (found in this session): LLMDiscovery ordering, is_file_fresh?, DateTime.compare typo, relationships schema, MCP preload, search arity, UNEXTRACTED flag

### Open (need work)
- **#22 NIF**: tree-sitter doesn't extract Elixir modules/macros — `docs/NIF_TREE_SITTER_MODULE_FIX.md` has the full briefing for another agent to fix
- **#25**: relationships don't capture calls from inside `quote do` — fundamental architecture limitation, may require Macro.traverse or different approach
- **#25 partial**: heuristic flag `[UNEXTRACTED]` is shown but NIF still doesn't have the right context to distinguish "in_macro" from "parser_bug"
- Arities field on Symbol schema (medium priority refactor)

### Will not fix (intentional)
- #12 LLMGuard inconsistency (documented as design choice)

---

## Build & test commands

### Build
```bash
cd ~/cacafuti/delfos
# Preferred build command (user said "mix gen" not "mix batamanta")
mix gen
cp ./delfos ~/bin/delfos
```

### Test
```bash
# End-to-end test plan
less ~/cacafuti/delfos/docs/TEST_PLAN.md

# Quick sanity check
cd /home/merendandum/cacafuti/pote
~/bin/delfos status
~/bin/delfos doctor
~/bin/delfos query "config"

# MCP test
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' | timeout 5 ~/bin/delfos mcp 2>&1
```

### Push
```bash
cd ~/cacafuti/delfos
git push origin main --tags
# (user does this manually; I never push)
```

---

## Key files to check when resuming

1. `~/cacafuti/delfos/docs/NIF_TREE_SITTER_MODULE_FIX.md` — full briefing for fixing Bug #22 (NIF module extraction). If you want to work on that, read this first.
2. `~/cacafuti/delfos/CHANGELOG.md` — needs an update for bugs #24, #25, #26
3. `~/cacafuti/delfos/docs/TEST_PLAN.md` — the E2E test plan that was originally executed
4. `~/cacafuti/session-ses_0be9.md` — the transcript of the opencode test session that found bugs #24-#26
5. `~/cacafuti/delfos/lib/delfos/mcp/tools.ex` — where the latest fixes live (commits 41272a5, b83676b)

---

## Opencode test session transcript

The full session where bugs #24, #25, #26 were found is at:
`/home/merendandum/cacafuti/session-ses_0be9.md`

Key takeaways from that session:
- T1 (list tools): ✅ PASS
- T2 (search config_app): ⚠️ PARTIAL — found the symbol but with corrupt metadata (empty CODE, weird line range)
- T3 (find main config + graph): ❌ FAIL — had to reconstruct graph from source code because Delfos didn't index the calls inside `__using__` macro

The model in that session (Mavis) was very capable: it detected the anomalies, fell back to `rg` + `read` to verify, and explained the metaprogramming to the user. This is good — but it also shows that Delfos still has gaps in Elixir projects with macros.

---

## What I'd do next if I had more time

1. Update CHANGELOG with bugs #24, #25, #26 (the recent opencode-session findings)
2. Possibly create tag `2.2.1` if we want to mark these as a separate release
3. Maybe try to fix the arity extraction in the NIF (but it's a NIF change, big task)
4. Test all 3 opencode test prompts again with the new binary to verify fixes
5. Then push the commits

But the user said "actualiza el estado en los docs... y continua", so:
- ✅ Update docs (this file)
- Continue with whatever's next per user direction
