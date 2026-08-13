# BENCHMARKS — Delfos Performance Analysis

> Living document. Updated as benchmarks evolve. Last run: 2026-08-13
> on AMD Ryzen AI 9 HX 370 (24 cores, 32GB RAM), Elixir 1.19.5, OTP 28.

## TL;DR — Where does the time go?

| Phase | Time/file | % of total |
|-------|-----------|------------|
| Scanner walking FS | ~7 μs/file | <0.1% |
| ElixirParser (AST) | ~65 μs/file | <1% |
| Repo.insert_all (batched) | ~1 ms/file | ~1% |
| **Embeddings (HTTP to Ollama)** | **50-500 ms/file** | **~98%** |

**Conclusion**: `delfos init` is not slow because of Elixir code. It's slow because
of embedding generation latency. Optimizing the Elixir pipeline further has
diminishing returns. The real wins are:
1. Use a faster embedding model
2. Use GPU if available
3. Reduce chunks per file (smaller granularity = less to embed)
4. Skip embedding files that don't have meaningful symbols

## Bench infrastructure

### Fixtures

`bench/fixtures.exs` generates three synthetic Elixir projects:

| Size | Files | Total LOC |
|------|-------|-----------|
| small | 10 | ~500 |
| medium | 100 | ~5,000 |
| large | 500 | ~25,000 |

Fixtures are cached under `bench/fixtures/{small,medium,large}/`. Re-running
is idempotent (only builds if missing).

### Bench scripts

All scripts are runnable via `mix run bench/<name>.exs`:

- `bench/scanner.exs` — find_files vs stream_files
- `bench/parser.exs` — AST vs regex
- `bench/chunker.exs` — File.read! vs File.stream!
- `bench/parser_memory.exs` — naive vs streaming acc
- `bench/parser_real.exs` — full ElixirParser.parse/2 pipeline
- `bench/config_manager.exs` — warm getters
- `bench/config_manager_cold.exs` — cold path + AES decrypt
- `bench/indexer.exs` — scan + AST parse pipeline
- `bench/pipeline.exs` — scan + parse + embedding (mock)
- `bench/run.exs` — runs all of the above

## Detailed results (host-specific)

### Scanner — `lib/delfos/indexer/scanner.ex`

| Operation | Size | Time | Throughput | Memory |
|-----------|------|------|------------|--------|
| `find_files/2` | 10 | 236 μs | 4.23 K/s | 72 KB |
| `find_files/2` | 100 | 557 μs | 1.79 K/s | 210 KB |
| `stream_files/3` | 10 | 240 μs | 4.16 K/s | 72 KB |
| `stream_files/3` | 100 | 585 μs | 1.71 K/s | 210 KB |

`stream_files` equals `find_files` for small projects. For large projects
(>100k files), `find_files` OOMs while `stream_files` stays O(1) in memory.

### Parser — `lib/delfos/parsers/elixir_parser.ex`

| Approach | Time/op | Memory |
|----------|---------|--------|
| `Code.string_to_quoted!` only | 34.4 μs | 63 KB |
| `string_to_quoted! + prewalk + counter` (streaming acc) | 34.9 μs | 65 KB |
| `string_to_quoted! + prewalk + acc list` (naive) | 38.7 μs | 78 KB |

The streaming acc refactor is 12% faster and 17% lighter. Real-world impact
when processing many files is bounded by the AST construction cost.

### Chunker — `lib/delfos/indexer/chunker.ex`

| Operation | Time/op | Memory |
|-----------|---------|--------|
| In-memory String.split | 0.66 μs | 0 B |
| `File.read!` cold I/O | 7.82 μs | 336 B |

File I/O is ~12x slower than pure string ops, but each file's I/O is only
~7 μs — negligible compared to AST parsing and embedding.

### Config Manager — `lib/delfos/config/manager.ex`

| Operation | Time | Notes |
|-----------|------|--------|
| `load/0` warm | 82 μs | Cached after first load |
| `indexing/0` | 82 μs | Cached |
| `embedding/0` | 89 μs | Cached |
| `llm/0` | 81 μs | Cached |
| **Cold start + decrypt (50 sections)** | **27.7 ms** | One-shot at app start |

Config is not the bottleneck — even cold start + AES decrypt is sub-30ms.

### Indexer pipeline

| Stage | Size | Time | Notes |
|-------|------|------|-------|
| Scan + AST parse | 10 | 2.26 ms | No DB, no embed |
| Scan + AST parse | 100 | 19.7 ms | |
| Scan + AST parse | 500 | 99.0 ms | |
| **+ Embedding mock (5ms/chunk)** | 10 | 284 ms | **125x slower** |
| **+ Embedding mock (5ms/chunk)** | 100 | 2.46 s | **125x slower** |
| **+ Embedding mock (5ms/chunk)** | 500 | 12.16 s | **123x slower** |

With realistic Ollama latency (50-100ms/chunk), a 1000-file project takes
**8-25 minutes** just in embedding. This is the bottleneck.

## Bugs found by benchmarks

### Scanner depth tracking (fixed in commit 069ac95)

**Bug**: `depth` was incremented on every processed path (file or dir),
not only on directory descent. For projects with >50 files in a flat layout
(`deps/`, `vendor/`), this triggered an early `max_depth` halt that
silently truncated the file list.

**Symptom**: `delfos scan` on a 500-file Elixir project missed most files
beyond depth 50. User would see "Indexed 50 files" when there are 500.

**Fix**: `depth` now only increments when descending into a subdirectory.

### Task.async_stream materialization (fixed in commit 8176dc6)

**Bug**: `Indexer.Streaming.run/3` did `Scanner.stream_files |> Enum.to_list() |> Task.async_stream(...)`,
materializing ALL file paths in memory before any parallel processing started.

**Symptom**: For a 10k-file project, 10k path strings sat in memory while
the first 4 workers processed them.

**Fix**: Removed `Enum.to_list/1` — the Stream flows directly into
`Task.async_stream`, which has real backpressure (pauses producer when
N tasks are in flight). Workers default bumped from 4 to `System.schedulers_online()`.

## Performance regression guards

`test/delfos/perf_regression_test.exs` asserts that key operations stay
under defined thresholds:

| Operation | Threshold |
|-----------|-----------|
| Scanner.find_files medium | <100ms |
| Scanner.stream_files medium | <100ms |
| ElixirParser medium | <100ms |
| Scan + parse large | <500ms |

Tagged with `:perf`. Run with:

```bash
mix test --only perf                     # only regression tests
mix test --exclude perf                  # exclude them for fast iteration
PERF_REGRESSION_MULTIPLIER=2.0 mix test --only perf   # for slow CI
```

## Optimization opportunities (not done — diminishing returns)

### 1. Two-stage pipeline (CPU + I/O)

Currently the indexer does everything per-file in one worker. Splitting into:
- Stage 1 (CPU-bound): scan + parse + chunk → produces chunks
- Stage 2 (I/O-bound): embed + DB insert

With separate concurrency levels (parse workers=24, embed workers=8-32 depending
on Ollama's parallel capacity), wall-time could be reduced ~30%. Diminishing
returns vs the 100x improvement from fixing the embedding bottleneck.

### 2. AST streaming without full materialization

`Code.string_to_quoted!` builds the entire AST before returning. For very
large files (>10k lines), this is a 500KB+ allocation per file. Alternative:
use `Code.Tokenizer` to stream tokens and extract symbols without building
the AST. Estimated 2-3x speedup for large files only.

### 3. Embedding cache hit rate

Currently no cache for embeddings — every chunk re-embedded on re-scan.
Adding an embedding cache (keyed by content hash) would make re-scans
O(1) for unchanged chunks. Estimated 50-90% wall-time reduction on re-scans.

### 4. Symbol graph incremental build

Currently `GraphBuilder.build/1` rebuilds the full graph per scan. An
incremental build (only affected files) would scale better.

## How to run the bench suite

```bash
# Build fixtures (only needed once)
mix run bench/fixtures.exs

# Run all benchmarks (~3 minutes total)
mix run bench/run.exs

# Run individual benchmarks
mix run bench/scanner.exs
mix run bench/parser.exs
mix run bench/pipeline.exs
mix run bench/parser_memory.exs
```

## Files added

```
bench/
├── fixtures.exs              # Project generator
├── scanner.exs               # find_files vs stream_files
├── parser.exs                # AST vs regex
├── chunker.exs               # File.read! vs streaming
├── parser_memory.exs         # Acc list vs counter
├── parser_real.exs           # Full ElixirParser pipeline
├── config_manager.exs        # Warm getters
├── config_manager_cold.exs   # Cold path + AES decrypt
├── indexer.exs               # Scan + parse pipeline
├── pipeline.exs              # Scan + parse + embed (mock)
└── run.exs                   # All benches
```
