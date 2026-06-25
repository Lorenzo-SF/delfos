# Delfos

> MCP server and code analysis tool for AI assistants.

Delfos indexes your codebase, builds a symbol graph, and exposes an MCP
API that AI assistants (Claude Desktop, Cursor, Zed, etc.) use to understand
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

The full workflow, in order. Each step depends on the previous one.

```bash
# 0. Verify your environment (optional but recommended the first time)
delfos doctor
# If anything fails, see "Troubleshooting" below.

# 1. Register a project (cd into it first)
cd /path/to/your/project
delfos init .

# 2. Full scan — creates embeddings, builds the symbol graph
delfos scan --full

# 3. (Optional) Generate LLM summaries for symbols
delfos summarize

# 4. Wire Delfos into your AI agent of choice
delfos integrate claude-code --yes     # or: opencode, cursor, aider, codex, zed, all

# 5. Start the MCP server (in another terminal, or as a background process)
delfos serve --mcp
```

### Verify it works

```bash
delfos status        # index coverage, projects, last scan
delfos models        # which models are active
delfos models --probe # actually ping the LLM and embedding endpoints
delfos query "main entry point"   # ad-hoc CLI search
```

### Troubleshooting

If `delfos doctor` reports a failure:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `PostgreSQL: cannot connect` | DB not running, wrong host/port/creds | `delfos config get llm url` and check `DB_HOST/DB_PORT/DB_USER/DB_PASS` env vars |
| `pgvector: not installed` | Extension not loaded | `psql -d delfos_dev -c 'CREATE EXTENSION vector;'` |
| `Embedding: not reachable` | llama-server not running on the configured port | Start it: see "Models" section below |
| `LLM: not reachable` | Same as above, different port | Same |
| `dim mismatch` | Changed embedding model but DB still has old vectors | `mix ecto.reset && delfos init .` |

Run `delfos doctor --json | jq '.results[] | select(.status!="ok")'` for a
machine-readable list of what's broken.

## MCP configuration

The fastest way to wire Delfos into your agent is `delfos integrate`:

```bash
delfos integrate claude-code --yes   # writes ~/.claude.json + ~/.claude/CLAUDE.md
delfos integrate opencode --yes      # writes ~/.config/opencode/config.json
delfos integrate all --yes           # all supported agents at once
```

Supported agents: `claude-code`, `opencode`, `cursor`, `aider`, `codex`, `zed`.

After integration, **start the MCP server**:

```bash
delfos serve --mcp
```

The agent will discover the 8 `delfos_*` tools (see below) the next time
it restarts. Make sure the project is already indexed (`delfos init .` +
`delfos scan --full`); otherwise the tools will return empty results.

### Manual configuration

If you'd rather wire it yourself, point your agent's MCP entry at the
`delfos` binary with `["serve", "--mcp"]` as args. Examples:

**Claude Desktop** (`claude_desktop_config.json`):
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

**OpenCode** (`~/.config/opencode/config.json`):
```json
{
  "mcp": {
    "delfos": {
      "command": "/path/to/delfos",
      "args": ["serve", "--mcp"],
      "type": "local"
    }
  }
}
```

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

## CLI

All output is rendered through `Alaja`, so messages get consistent
icon-prefixed styling (`✓` success, `✗` error, `⚠` warning, `ℹ` info).

| Command | Purpose |
|---------|---------|
| `delfos init` | Register a project and run the first full scan |
| `delfos scan [--full]` | Re-scan (incremental by default) |
| `delfos query <text>` | Hybrid search |
| `delfos explain <name>` | LLM explanation of a symbol |
| `delfos summarize` | Generate LLM summaries |
| `delfos audit` | Technical debt report |
| `delfos graph callers\|callees\|impact\|cycles <name>` | Graph exploration |
| `delfos context` | Generate AGENTS.md / CLAUDE.md context |
| `delfos config show\|set\|get\|preset` | Manage `~/.config/delfos/delfos.conf` |
| `delfos integrate [agent]` | Configure MCP integration for Claude / Cursor / Zed |
| `delfos serve --mcp` | Run the MCP stdio server |
| `delfos watch` | File-system watcher + auto re-indexing |
| `delfos doctor [--fix]` | Full diagnostic |
| `delfos status` | Index + project status |

## Configuration

Delfos reads `~/.config/delfos/delfos.conf` (TOML) with environment variable
overrides. See `config/config.exs` for all options. Main sections:

- `[embedding]` — embedding provider, model, dimension, batch size
- `[llm]` — LLM provider, model, max_tokens per use case
- `[retrieval]` — RRF weights, top_k, final_k
- `[indexing]` — ignored directories, max chunk tokens
- `[analysis]` — churn analysis window

## Models

Delfos routes every LLM and embedding call through one of three providers.
Choose via `delfos config preset <name>` or edit `~/.config/delfos/delfos.conf`
directly.

### Local (default, no API key needed)

Two `llama-server` processes running on your machine:

```bash
# Embedding server (port 9998)
llama-server -m bge-m3-q4_k_m.gguf --port 9998 --embedding \
  --threads 4 --batch-size 64 --ctx-size 2048 \
  --mlock --no-mmap --flash-attn --host 127.0.0.1

# LLM server (port 8080)
llama-server -m Qwen2.5-Coder-3B-Instruct-Q4_K_M.gguf --port 8080 \
  --threads 6 --batch-size 128 --ctx-size 8192 \
  --mlock --no-mmap --flash-attn --host 127.0.0.1
```

Recommended models fit in ~4 GB VRAM combined. Anthropic embeddings are not
provided locally — the doctor will warn if you try to mix providers that way.

### OpenAI

```bash
delfos config preset openai        # text-embedding-3-small + gpt-4o-mini (dim=1536)
delfos config preset openai-large  # text-embedding-3-large + gpt-4o    (dim=3072)
delfos config set llm api_key sk-...
delfos config set embedding api_key sk-...
mix ecto.reset && delfos init .    # required when changing dim
```

### Anthropic

```bash
delfos config preset anthropic
delfos config set llm api_key sk-ant-...
```

Anthropic provides chat only — embeddings stay on whichever provider you
had configured (default: local).

### Check what's active

```bash
delfos models            # static view
delfos models --probe    # actually ping each endpoint
```

## Ecosystem

Delfos is part of Lorenzo-SF's Elixir OSS ecosystem and reuses them
extensively:

- **Arrea** — async process orchestrator (used for parallel retrieval,
  file processing, external commands with timeout)
- **Alaja** — terminal rendering framework (used for all CLI output)
- **Apero** — utility library for system operations (used by `delfos doctor`)
- **Candil** — LLM inference and model management (used for summaries)

## Documentation

- `README.md` — this file (English)
- `docs/README.es.md` — Spanish version
- `SPEC.md` — complete functional specification
- `CHANGELOG.md` — release notes

## License

MIT — see [LICENSE.md](LICENSE.md).
