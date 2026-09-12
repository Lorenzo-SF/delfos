# delfos — ressurrection_fase_9: análisis meticuloso

> **Fecha**: 2026-09-12
> **Rama**: `ressurrection_fase_9`
> **Tamaño**: 153 módulos, ~22,934 LOC

---

## 1. Dominio

delfos es el **knowledge engine** del ecosistema:
- TreeSitter NIF (34 lenguajes — `native/tree_sitter_nif/`)
- Indexer Broadway pipeline
- Hybrid search (vector + BM25 + graph + RRF)
- MCP server (8+ tools: search, symbol, context, callers, callees, impact, audit, files)
- AI integrations (Claude Code, OpenCode, Cursor, Aider, Codex, Zed)
- Safe writes (timestamped backups)
- CLI self-diagnosing (`delfos doctor`)

**Migración zaguan → delfos**: zaguan tiene una versión muy primitiva de esto:
- `Zaguan.RAG` (514 LOC, sin indexer, sin graph, sin watcher)
- `Zaguan.MCP.Server` (375 LOC, 11 tools built-in, 4 zaguan_* tools)
- `Zaguan.RAGGraph` (143 LOC, regex fallback)

Migrar zaguan → delfos le daría: indexer Broadway, real TreeSitter, real hybrid
search, real safe writes, real MCP server con los 8 tools prometidos.

---

## 2. Análisis

### P0-1 — `Delfos.MCP.Server` ya usa `Task.Supervisor.async_nolink` ✅

**Archivo**: `lib/delfos/mcp/server.ex:546-575`
**Estado**: correctamente implementado.
- `Task.Supervisor.async_nolink` evita crashes propagados.
- Timer `Process.send_after` con timeout.
- `try/rescue/catch` envuelve el tool dispatch.
- `secure_compare` para auth tokens.
- **Veredicto**: production-grade.

### P0-2 — `Delfos.Indexer.GraphBuilder` 473 LOC

**Archivo**: `lib/delfos/indexer/graph_builder.ex`
**Tipo**: SRP
**Impacto**: graph build + persist + cache invalidation en un módulo.
**Decisión**: deferido (refactor mayor).

### P0-3 — TreeSitter NIF build

El NIF compila en delfos (target/debug). Para zaguan, deberíamos **reusar el
NIF de delfos** o **portarlo**. La rama ressurrection_fase_1 de zaguan ya tiene
un scaffold, pero está incompleto.

---

## 3. Fix aplicado

delfos ya está bien implementado. **0 fixes urgentes**.

**Decisión**: 1 commit — añadir doc de auditoría + nota sobre cómo
zaguan debe consumir delfos via `deps` en vez de reimplementar.
