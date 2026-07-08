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
