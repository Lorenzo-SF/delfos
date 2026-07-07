# Delfos commands × LLM usage

Audit of which `delfos <cmd>` actually need a working LLM endpoint
(embedding +/or chat). Read this before commenting things out.

## Endpoint summary

Delfos exposes **two** provider endpoints via `Delfos.Config.Manager`:

| Endpoint | Used for            | Default section  |
|----------|---------------------|------------------|
| Embedding | 1024-dim vectors  | `embedding`      |
| Chat     | summaries, explain, query, context summaries | `llm` |

Both speak OpenAI-compatible HTTP (the local llama-server emits the
right shape on `/v1/embeddings` and `/v1/chat/completions`).

## Per-command matrix

| Command    | Embedding | Chat  | Failure mode if missing                                     |
|------------|-----------|-------|-------------------------------------------------------------|
| `init`     | —         | —     | n/a (no LLM call)                                            |
| `scan`     | **MUST**  | —     | Every file's symbols get an embedding; failure breaks scan  |
| `query`    | **MUST**  | —     | Pure vector search; embeddings required                      |
| `explain`  | **MUST**  | **MUST** | Needs embeddings (lookup) + chat (LLM summary/explanation) |
| `summarize`| **MUST**  | **MUST** | Iterates all symbols; calls embed + chat per symbol       |
| `context`  | yes       | no    | Embeds the queried symbol name; degrades to no related chunks if missing |
| `audit`    | —         | —     | Pure SQL; no LLM                                             |
| `graph`    | —         | —     | Pure SQL; no LLM                                             |
| `mcp`      | **MUST**  | **MUST** | The MCP tools `search`, `lookup`, `context`, `explain` all hit LLM |
| `config`   | —         | —     | Just edits the config file                                   |
| `doctor`   | —         | —     | Probes providers but degrades gracefully to a `:warn`       |
| `status`   | —         | —     | DB count only                                                 |
| `integrate`| —         | —     | Writes agent config files                                    |
| `watch`    | inherits from `scan` | — | Watcher delegates to scan; same MUST requirements         |

## Categories

### MUST have LLM (5 commands)
`scan`, `query`, `explain`, `summarize`, `mcp`.

Without a working `embedding.url` AND `llm.url`, these either crash
or return empty results.

### SHOULD have LLM, degrades gracefully (2 commands)
`context` (no related chunks if embed down), `watch` (silently does
nothing useful if scan can't embed).

### Probes LLM (1 command)
`doctor` — actively probes both endpoints as a sanity check.

### No LLM at all (the rest)
`init`, `audit`, `graph`, `config`, `status`, `integrate` work
without any LLM running.

## Operational rule of thumb

> If you run `llama-run gpt_oss medium` and `llama-run embed` in
> two terminals, the **only** commands you can run are `audit`,
> `graph`, `config`, `status`, `integrate`, `init` and `doctor`
> (probes will pass). To do anything useful you need both servers
> up.

## Where each provider is configured

Both endpoints come from `~/.config/delfos/config.json`:

```jsonc
{
  "embedding": {
    "provider": "local",
    "url":      "http://127.0.0.1:9998",
    "model":    "embed",
    "dim":      1024,
    "batch_size": 48,
    "api_key":   "sk-local-dev-key"
  },
  "llm": {
    "provider": "local",
    "url":      "http://127.0.0.1:9999",
    "model":    "gpt-oss",
    "summarize_max_tokens": 180,
    "explain_max_tokens":   600,
    "query_max_tokens":     512,
    "api_key":   "sk-local-dev-key"
  }
}
```

Use `delfos config set <section> <key> <value>` to edit without hand-rolling JSON, or run the helper script in `bin/register-local-llms.sh` which does the same end-to-end.