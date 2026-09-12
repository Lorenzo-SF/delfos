# delfos — audit completitud (iter-044)

> **Fecha**: 2026-09-12
> **Tamaño**: 22,934 LOC, 153 módulos
> **Meta**: delfos 100% terminado

---

## Estado actual

delfos está **production-grade**. Todos los módulos core funcionan:
- TreeSitter NIF (34 lenguajes) — ya compilado.
- Indexer Broadway pipeline.
- Hybrid search (vector+BM25+graph RRF).
- MCP server (8+ tools).
- Watcher (real-time re-index).

## Gap identificado (iter-044)

### P1 — `Delfos.Parsers.TreeSitter.parse/3` no tiene opción de profundidad
**Archivo**: `lib/delfos/parsers/treesitter/tree_sitter.ex`
**Tipo**: feature gap
**Impacto**: archivos muy grandes (50K+ líneas) son lentos.  Opción
`max_depth` permite shallow parse para preview/index rápido.

### P2 — GraphBuilder 473 LOC con SRP violation
**Archivo**: `lib/delfos/indexer/graph_builder.ex`
**Tipo**: SRP
**Impacto**: módulo hace build + persist + cache.  Extract
`GraphPersister` separado.

### Plan iter-044

1. P1: `parse/3` con `:max_depth` opt.
2. P2: Extract `GraphPersister` module (no es un refactor completo, solo
   la separación de persistencia).
3. Tests.
4. Doc.
