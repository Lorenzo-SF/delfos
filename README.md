# Delfos

> MCP server and code analysis tool for AI assistants.

Delfos indexes your codebase, builds a symbol graph, and exposes an MCP API
that AI assistants (Claude Desktop, Cursor, Zed, etc.) use to understand
your code with surgical precision — without hallucinating about what
they haven't seen.

## Features

- **Hybrid search** — semantic vector + BM25 + graph with Reciprocal Rank Fusion
- **40+ languages** — via Tree-sitter NIFs with regex fallback
- **Real-time re-indexing** — Watcher detects changes and notifies the MCP client
- **BFS impact analysis** — know what breaks before refactoring
- **Technical debt metrics** — churn, coupling, instability, dependency cycles
- **Multi-provider LLM** — local (OpenAI-compat), OpenAI, Anthropic

## Installation

### From source (recommended for development)

```bash
git clone https://github.com/Lorenzo-SF/delfos
cd delfos
mix deps.get
mix compile
```

### As a binary (via Batamanta)

See the [releases page](https://github.com/Lorenzo-SF/delfos/releases) for
pre-built escripts that bundle Elixir and OTP — no Elixir install required.

## Quick start

```bash
# 1. Register a project (cd into it first)
cd /path/to/your/project
delfos init .

# 2. Full scan (creates embeddings, builds symbol graph)
delfos scan --full

# 3. (Optional) Generate LLM summaries for symbols
delfos summarize

# 4. Start the MCP server
delfos serve --mcp
```

## MCP configuration

### Claude Desktop (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "delfos": {
      "command": "/path/to/delfos",
      "args": ["serve", "--mcp"]
    }
  }
}
```

### Cursor / Zed

Equivalent configuration — point the MCP entry to the `delfos` binary with
`serve --mcp` as args.

## MCP tools available

| Tool | Description |
|------|-------------|
| `delfos_search` | Hybrid search across the index |
| `delfos_symbol` | Full symbol details with LLM summary |
| `delfos_context` | Compact context for a task |
| `delfos_callers` | What calls a symbol |
| `delfos_callees` | What a symbol calls |
| `delfos_impact` | BFS impact analysis before refactoring |
| `delfos_audit` | Technical debt metrics |
| `delfos_files` | Indexed file structure |

## Architecture

```
┌────────────────────────────────────────────────────────┐
│  MCP Server (JSON-RPC 2.0 over stdio)                 │
│  └── Delfos.MCP.Tools (8 tools)                       │
├────────────────────────────────────────────────────────┤
│  Indexer                                             │
│  ├── Scanner        (find files, SHA256 detect)      │
│  ├── FileProcessor  (parse + embed + persist)        │
│  ├── GraphBuilder   (xref + import graph + cycles)   │
│  └── Watcher        (FSEvents/inotify re-indexing)   │
├────────────────────────────────────────────────────────┤
│  Retrieval (parallel via Arrea)                       │
│  ├── HybridSearch  (vector + BM25 + graph → RRF)     │
│  ├── VectorSearch  (pgvector cosine)                  │
│  ├── BM25Search    (PostgreSQL FTS)                   │
│  ├── GraphSearch   (BFS on symbol graph)             │
│  └── Reranker      (Reciprocal Rank Fusion)          │
├────────────────────────────────────────────────────────┤
│  Parsers (40+ languages)                             │
│  ├── TreeSitter NIF (Rust, AST-based)                │
│  ├── Specialized   (Dart, HCL, YAML)                │
│  └── GenericParser (regex fallback)                 │
├────────────────────────────────────────────────────────┤
│  LLM Client (multi-provider, multi-use-case)        │
│  ├── :local      (OpenAI-compat, llama.cpp)         │
│  ├── :openai     (OpenAI API)                        │
│  └── :anthropic  (Anthropic API)                     │
└────────────────────────────────────────────────────────┘
```

## Configuration

Delfos reads `~/.config/delfos/delfos.conf` (TOML) with environment variable
overrides. See `config/config.exs` for all options. Main sections:

- `[embedding]` — embedding provider, model, dimension, batch size
- `[llm]` — LLM provider, model, max_tokens per use case
- `[retrieval]` — RRF weights, top_k, final_k
- `[indexing]` — ignored directories, max chunk tokens
- `[analysis]` — churn analysis window

## Ecosystem

Delfos is part of Lorenzo-SF's Elixir OSS ecosystem:

- **Arrea** — async process orchestrator (used for parallel retrieval)
- **Alaja** — terminal rendering framework (used for the CLI)
- **Apero** — utility library for system operations
- **Candil** — LLM inference and model management (used for summaries)

## License

MIT — see [LICENSE.md](LICENSE.md).

---

**For Spanish documentation, see [README_ES.md](README_ES.md).**
