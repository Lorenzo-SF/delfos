# delfos — deep audit (iter-051) — porque zaguan es delfos potenciado

> **Fecha**: 2026-09-12
> **Mandato**: delfos debe estar al 100% porque zaguan depende de él.

---

## Estado actual

- 23,020 LOC, 153 módulos
- 52 tests files
- TreeSitter NIF (34 lenguajes) ✅
- Indexer Broadway ✅
- Hybrid search (vector+BM25+graph RRF) ✅
- MCP server (8+ tools) ✅
- Watcher (real-time) ✅
- Cross-reuse con apero ✅

## Gaps identificados

### P1 — `Delfos.Indexer.Chunker.chunk_text/3` no es público
**Archivo**: `lib/delfos/indexer/chunker.ex`
**Tipo**: API completeness
**Impacto**: hay un `chunk_symbol/4` y `chunk_file/3` pero no un helper
genérico `chunk_text(content, opts)` para callers externos.

### P1 — `Delfos.MCP.Server.tool_timeout_ms/0` no configurable
**Archivo**: `lib/delfos/mcp/server.ex`
**Tipo**: configurability
**Impacto**: el timeout hardcoded de 30s no se puede override por env var.

### P2 — `Delfos.Statistics.format/2` helper
**Archivo**: `lib/delfos/statistics.ex`
**Tipo**: UX
**Impacto**: stats no tienen un formatter reusable.

### P2 — `Delfos.LLM.CandilBridge` rate limit
**Archivo**: `lib/delfos/llm/candil_bridge.ex`
**Tipo**: reliability
**Impacto**: el bridge no respeta rate limits — bombardea al provider.

### Plan iter-051

1. P1: `Delfos.Indexer.Chunker.chunk_text/2` — public API.
2. P1: `Delfos.MCP.Server.tool_timeout_ms_from_env/0` — env override.
3. P2: `Delfos.Statistics.format_summary/1` — public formatter.
4. P2: `Delfos.LLM.CandilBridge` rate limiting via Apero.
5. Tests.
6. Doc.

---

**Sign-off**: Mavis (root session) — 2026-09-12.
