# Delfos commands × LLM usage (v2.3.0)

Audit of which `delfos <cmd>` actually need a working LLM endpoint
(embedding +/or chat), and the `--llm-less` / `--with-explanation`
flags that change each command's LLM dependency.

## Endpoint summary

Delfos exposes **two** provider endpoints via `Delfos.Config.Manager`:

| Endpoint | Used for            | Default section  |
|----------|---------------------|------------------|
| Embedding | 1536-dim vectors  | `embedding`      |
| Chat     | summaries, explain, query, context summaries | `llm` |

Both speak OpenAI-compatible HTTP (the local llama-server emits the
right shape on `/v1/embeddings` and `/v1/chat/completions`).

> **Note (v2.3.0):** `embedding.dim` and `embedding.model` are
> compile-time fixed in `config/config.exs` and cannot be changed at
> runtime. Default: `jina-code-embeddings-1.5b-Q8_0` (1536-dim).

## Per-command matrix (v2.3.0)

| Command       | Embedding | Chat  | `--llm-less` | `--with-explanation` | Failure mode if missing |
|---------------|-----------|-------|--------------|----------------------|----------------------------|
| `init`        | —         | —     | n/a          | n/a                  | n/a (no LLM call)          |
| `scan`        | **MUST**  | —     | n/a          | n/a                  | Every file's symbols get an embedding; failure breaks scan |
| `query`       | optional  | —     | `--llm-less` skips vector engine, falls back to BM25 + graph | n/a | `--llm-less` mode works without embeddings |
| `explain`     | —         | yes   | `--llm-less` skips LLM call, shows cached summary only | n/a | Without cached summary, prints warning to run `delfos summarize` |
| `summarize`   | **MUST**  | **MUST** | n/a (always LLM) | n/a | Iterates all symbols; calls embed + chat per symbol |
| `audit`       | —         | optional | `--llm-less` skips LLM narrative | `--with-explanation` adds LLM diagnosis | Without LLM, shows deterministic fallback |
| `graph`       | —         | —     | n/a          | n/a                  | Pure SQL; no LLM           |
| `agents`      | —         | optional | `--llm-less` skips LLM exec summary | `--with-explanation` prepends LLM exec summary | Without LLM, shows deterministic summary |
| `mcp`         | **MUST**  | **MUST** | n/a | n/a | The MCP tools `search`, `lookup`, `context`, `explain` all hit LLM |
| `config`      | —         | —     | n/a          | n/a                  | Just edits the config file |
| `doctor`      | —         | —     | n/a          | n/a                  | Probes providers; degrades gracefully |
| `status`      | —         | —     | n/a          | n/a                  | DB count only             |
| `integrate`   | —         | —     | n/a          | n/a                  | Writes agent config files |

## Removed in v2.3.0

- `delfos watch` — merged into `delfos mcp`
- `delfos serve` — alias of `delfos mcp`
- `delfos context` — alias of `delfos agents`
- `delfos stadistics` — typo, use `delfos status --stats`
- `delfos preset`/`setup`/`models` (top-level) — use `delfos config <sub>`
- `delfos config wizard` — use `delfos config setup llm`

## Categories

### MUST have LLM (4 commands)
`scan`, `summarize`, `mcp`, and `query` by default.

### Optional LLM (3 commands)
`explain`, `audit`, `agents` — opt-in via `--with-explanation`. Without
it they show static info only.

### LLM-resilient (3 commands)
`query --llm-less`, `explain --llm-less`, `audit --llm-less` — skip
the LLM and use cached data or simpler algorithms (BM25 + graph,
deterministic fallback, etc.).

### No LLM at all
`init`, `graph`, `config`, `status`, `doctor`, `integrate`, `version`
work without any LLM running.

## Operational rule of thumb

> If you run `llama-run embed` and `llama-run gpt_oss medium` in two
> terminals, every command works. With `--llm-less` flags you can
> still run `query`, `explain`, and `audit` if only the chat server
> is down.

## Where each provider is configured

Both endpoints come from `~/.config/delfos/config.json` (encrypted
API keys with AES-256-GCM via Apero.Crypto.Cipher).

```jsonc
{
  "embedding": {
    "provider": "local",
    "url":      "http://127.0.0.1:9998",
    "dim":      1536,
    "batch_size": 48,
    "api_key":   "sk-local-dev-key"
  },
  "llm": {
    "provider": "local",
    "url":      "http://127.0.0.1:9999",
    "model":    "gpt-oss",
    "explain_max_tokens":   600,
    "query_max_tokens":     512,
    "api_key":   "sk-local-dev-key"
  }
}
```

Use `delfos config set <section> <key> <value>` to edit without hand-rolling JSON, or run `scripts/register-local-llms.sh` which does the same end-to-end.