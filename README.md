# Delfos

> MCP server and code analysis tool for AI assistants.

Delfos indexes your codebase, builds a symbol graph, and exposes an MCP
API that AI assistants (Claude Code, Cursor, OpenCode, Aider, Codex, Zed)
use to understand your code with surgical precision — without
hallucinating about what they haven't seen.

## Features

- **Hybrid search** — semantic vector + BM25 + graph with Reciprocal Rank Fusion
- **40+ languages** — via Tree-sitter NIFs with regex fallback
- **Real-time re-indexing** — Watcher detects changes and notifies the MCP client
- **BFS impact analysis** — know what breaks before refactoring
- **Technical debt metrics** — churn, coupling, instability, dependency cycles
- **Multi-provider LLM** — local (OpenAI-compat), OpenAI, Anthropic
- **6 AI agents wired up** — Claude Code, OpenCode, Cursor, Aider, Codex, Zed
- **Safe integration writes** — every overwrite creates a timestamped backup
- **Self-diagnosing CLI** — `delfos doctor` finds what is broken and how to fix it

## Installation

### From source (recommended for development)

```bash
git clone https://github.com/Lorenzo-SF/delfos
cd delfos
mix deps.get
mix compile
```

Delfos requires **Elixir 1.19.5+** and **OTP 28+**. See
`.tool-versions` for the exact versions used in CI.

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
| `PostgreSQL: cannot connect` | DB not running, wrong host/port/creds | `delfos config get embedding url` and check `DB_HOST/DB_PORT/DB_USER/DB_PASS` env vars |
| `pgvector: not installed` | Extension not loaded | `psql -d delfos_dev -c 'CREATE EXTENSION vector;'` |
| `Embedding: not reachable` | llama-server not running on the configured port | Start it: see "Models" section below |
| `LLM: not reachable` | Same as above, different port | Same |
| `dim mismatch` | Changed embedding model but DB still has old vectors | `mix ecto.reset && delfos init .` |

Run `delfos doctor --json | jq '.results[] | select(.status!="ok")'` for a
machine-readable list of what's broken.

## CLI reference

Every command supports `--help` and `-h`.

| Command | Purpose |
|---------|---------|
| `delfos init [path]` | Register a project and run the first full scan |
| `delfos scan [--full] [--workers N]` | Re-scan (incremental by default) |
| `delfos query <text> [--kind K] [--level L] [-n N] [--format json]` | Hybrid search |
| `delfos explain <name> [--fresh]` | LLM explanation of a symbol |
| `delfos audit [--file <path>]` | Technical debt report |
| `delfos summarize [--level 3\|4] [--force]` | Generate LLM summaries |
| `delfos graph callers\|callees\|impact\|cycles <name>` | Graph exploration |
| `delfos context [--output DIR] [--symbol NAME]` | Generate AGENTS.md / CLAUDE.md |
| `delfos config show\|set\|get\|preset\|init` | Manage `~/.config/delfos/delfos.conf` |
| `delfos integrate [agent] [--yes]` | Configure MCP integration for AI agents |
| `delfos serve --mcp` | Run the MCP stdio server |
| `delfos watch` | File-system watcher + auto re-indexing |
| `delfos doctor [--fix] [--interactive] [--json]` | Full diagnostic |
| `delfos doctor --db-only\|--llm-only` | Subset of checks |
| `delfos models [--probe]` | Show active embedding/LLM models |
| `delfos status` | Index + project status |
| `delfos version` | Installed version |
| `delfos --help` | Show global help |

## AI agent integrations

Delfos can wire itself into 6 AI coding agents. Each one writes the
config file the agent actually reads (verified by tests against the
real parsers in v0.3.3):

| Agent | Config files written | Format |
|-------|---------------------|--------|
| **claude-code** | `~/.claude.json` + `~/.claude/CLAUDE.md` + `~/.claude/settings.json` | JSON `mcpServers.{name}.{type,command,args}` + Markdown + JSON `permissions.allow[]` |
| **opencode** | `~/.config/opencode/config.json` + `.opencode/AGENTS.md` | JSON `mcp.{name}.{command,args,type:"local"}` + Markdown |
| **cursor** | `.cursor/mcp.json` + `.cursor/rules/delfos.mdc` | JSON `mcpServers.{name}.{command,args}` + MDC with YAML frontmatter |
| **aider** | `.aider.conf.yml` + `AGENTS.md` | YAML with merged `read:` list (no duplicate-key) |
| **codex** | `~/.codex/config.toml` | TOML `[mcp_servers.delfos].command` + `.args` |
| **zed** | `~/.config/zed/settings.json` | JSON `context_servers.{name}.command.{path,args}` |

### Quick start with any agent

```bash
delfos integrate claude-code --yes   # writes ~/.claude.json + ~/.claude/CLAUDE.md
delfos integrate opencode --yes      # writes ~/.config/opencode/config.json
delfos integrate all --yes           # all 6 agents at once
```

After integration, start the MCP server:

```bash
delfos serve --mcp
```

The agent will discover the 8 `delfos_*` tools the next time it
restarts. Make sure the project is already indexed (`delfos init .` +
`delfos scan --full`); otherwise the tools will return empty results.

### Safe writes

Every integration write goes through `safe_write/2`, which creates a
timestamped backup (`<path>.bak-<unix_seconds>`) before overwriting
any existing file. You can roll back any change with `cp ~/.claude.json.bak-1782374982 ~/.claude.json`.

If you re-run `delfos integrate <agent>` twice:

- It detects Delfos is already configured (no-op).
- It preserves your other MCP servers (claude-code `mcpServers.github`,
  codex `[mcp_servers.github]`, etc.).
- It merges the `read:` list for aider without producing a duplicate-key YAML error.

### Manual configuration

If you'd rather wire it yourself, point your agent's MCP entry at the
`delfos` binary with `["serve", "--mcp"]` as args:

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

**Codex** (`~/.codex/config.toml`):
```toml
[mcp_servers.delfos]
command = "/path/to/delfos"
args = ["serve", "--mcp"]
```

**Zed** (`~/.config/zed/settings.json`):
```json
{
  "context_servers": {
    "delfos": {
      "command": {
        "path": "/path/to/delfos",
        "args": ["serve", "--mcp"]
      }
    }
  }
}
```

## MCP tools

Delfos exposes 8 tools via JSON-RPC 2.0 over stdio:

| Tool | Purpose |
|------|---------|
| `delfos_search` | Hybrid search across the index |
| `delfos_symbol` | Full symbol details with LLM summary |
| `delfos_context` | Compact context for a task |
| `delfos_callers` | What calls a symbol |
| `delfos_callees` | What a symbol calls |
| `delfos_impact` | BFS impact analysis before refactoring |
| `delfos_audit` | Technical debt metrics |
| `delfos_files` | Indexed file structure |

See `docs/MCP_TOOLS.md` for sample output for every tool.

## Models

Delfos routes every LLM and embedding call through one of three providers.
Choose via `delfos config preset <name>` or edit
`~/.config/delfos/delfos.conf` directly.

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
provided locally — `delfos doctor` will warn if you try to mix providers that way.

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
delfos models            # static view (with masked API keys)
delfos models --probe    # actually ping each endpoint + check index dim
```

## Configuration

Delfos reads `~/.config/delfos/delfos.conf` (TOML) with environment variable
overrides. See `config/config.exs` for all options. Main sections:

- `[embedding]` — embedding provider, model, dimension, batch size
- `[llm]` — LLM provider, model, max_tokens per use case
- `[retrieval]` — RRF weights, top_k, final_k
- `[indexing]` — ignored directories, max chunk tokens
- `[analysis]` — churn analysis window

**Priority order** (highest wins):

1. Environment variables (e.g. `EMBED_URL`, `LLM_MODEL`, `DB_HOST`)
2. `~/.config/delfos/delfos.conf`
3. Built-in defaults in `mix.exs`

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
│  ├── GraphSearch   (BFS on symbol graph)              │
│  └── Reranker      (Reciprocal Rank Fusion)           │
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

## Ecosystem

Delfos is part of Lorenzo-SF's Elixir OSS ecosystem and reuses them
extensively:

- **Arrea** — async process orchestrator (used for parallel retrieval,
  file processing, external commands with timeout)
- **Alaja** — terminal rendering framework (used for all CLI output)
- **Apero** — utility library for system operations
- **Botica** — diagnostic runner that powers `delfos doctor`
- **Candil** — LLM inference and model management (used for summaries)
- **Pote** — colour and theme utilities

## Documentation

- `README.md` — this file (English)
- `docs/README.es.md` — Spanish version
- `SPEC.md` — complete functional specification (with v0.3.3 mapping in §20)
- `docs/MCP_TOOLS.md` — reference for the 8 MCP tools with sample output
- `CONTRIBUTING.md` — how to set up a dev environment and submit PRs
- `CHANGELOG.md` — release notes

## License

MIT — see [LICENSE.md](LICENSE.md).
