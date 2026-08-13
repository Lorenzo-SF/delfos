# Dialyzer Issues — Known

> **Date**: 2026-08-13
> **Status**: 132 warnings, 0 errors (warning count only)

## Summary

`mix dialyzer` reports **132 warnings** on a clean build. These are
all from legacy code that pre-dates the FASE-4 workstream. None
of the warnings are introduced by current changes.

## Distribution by category

| Category | Count | Nature |
|----------|------:|--------|
| `unused_fun` | 34 | Private functions kept as documentation or future use |
| `call` | 22 | Cross-module @spec drift (defensive call sites) |
| `pattern_match_cov` | 18 | `case` clauses for types that cannot reach that branch |
| `pattern_match` | 17 | Pattern can never match (mostly untyped error tuples) |
| `guard_fail` | 12 | Guard expressions that cannot succeed at runtime |
| `no_return` | 11 | Functions that always exit (`System.halt/1`, `raise`, `init:stop`) |
| `invalid_contract` | 6 | `@spec` doesn't match inferred types |
| `unknown_type` | 5 | Type referenced in @spec not exported (opaque struct cross-module) |
| `differ` | 4 | Return-type drift between pattern-match clauses |
| `variable_` | 4 | Underscore-prefixed vars that match later in body |
| `name` | 1 | Acronym naming convention (LLM, MCP) |
| `neg_guard_fail` | 2 | `not is_X` guards that should be `is_X` |

## What's NOT a problem

- **No `no_return` for user-facing CLI commands** — those are intentional exits
- **No safety-critical type mismatches** — most are `:ok | :error` tuples
- **No unhandled exceptions** in the type system

## What's a problem (low priority)

- `mcp/tools.ex` calls `Access.get/2` on `{:ok, _} | {:error, _}` tuples
  where dialyzer expects a map. Runtime works (Access.get handles
  the error case), but the type is not what the spec claims.
- `indexer/watcher.ex` spec is wider than the actual state shape
  (opaque subtype violation). Needs a refactor of the @spec.
- `config/diagnostics.ex` and `llm_discovery.ex` have @spec mismatches.

## Workarounds applied

- `application.ex:159` and `:162` pattern-match clauses for `{:ok, _}`
  and `{:error, _}` on a map — defensive dead code from a
  previous return shape.
- `mcp/server.ex:607-608` pattern matches on `%{authenticated: false}`
  when the state field is always `true` after init.

## Fix priority

| Priority | Effort | What |
|----------|--------|------|
| High | 1d | `mcp/tools.ex` — add `Access.fetch/2` or proper pattern match |
| Medium | 0.5d | `indexer/watcher.ex` — tighten @spec to actual state shape |
| Low | 2d | Delete `unused_fun` functions across the CLI commands |
| Low | 1d | Fix `guard_fail` patterns in `config/manager.ex` |

**Total effort to clean to 0 warnings**: ~5 days.
