# Delfos commands × LLM usage (v2.5.0)

Audit of which `delfos <cmd>` actually need a working LLM endpoint
(embedding +/or chat), and the `--llm-less` / `--with-explanation`
flags that change each command's LLM dependency.

## What's new since v2.3.0

- **Removed**: `delfos thinker_*` config keys (v2.4.0, commit
  `ccbbedb`). The idea of a separate "thinking" endpoint was
  dropped — separate `[summarize]` section is the canonical override
  for summarise-time config instead.
- **Removed**: `scripts/llm-server.sh` (v2.3.0). Use the
  `llama-run` wrapper (`llama-run embed`, `llama-run gpt_oss medium`)
  or run `llama-server` directly.
- **Added**: `delfos config migrate-local` (v2.5.0) — explicit
  version of the auto-migration that reverts stale OpenAI/Anthropic
  configs to `:local`.
- **Added**: `delfos config setup llm` auto-arranca el embed server
  via `ensure_embedding_server/0` (v2.4.0, commit `655b8b9`) cuando
  el `LLMDiscovery` lo detecta caído.
- **Added**: `Arrea.CircuitBreaker` envuelve cada llamada Anthropic
  chat (v2.4.0, commit `4580849`). Tras N fallos consecutivos, el
  breaker abre y `delfos explain` falla rápido con un mensaje claro
  en lugar de esperar el timeout completo.
- **Added**: `[summarize]` section (v2.4.0+) para override de
  summarize-time config. Si está presente, se prefiere sobre `[llm]`
  para summarise. Si no, cae a `[llm]` (backwards-compat).

## Endpoint summary

Delfos exposes **two** provider endpoints via `Delfos.Config.Manager`:

| Endpoint | Used for            | Default section  | Compile-time fixed? |
|----------|---------------------|------------------|--------------------|
| Embedding | 1536-dim vectors  | `embedding`      | Yes (model + dim) |
| Chat     | summaries, explain, query, context summaries | `llm` (or `summarize` if present) | No |

Both speak OpenAI-compatible HTTP (the local llama-server emits the
right shape on `/v1/embeddings` and `/v1/chat/completions`).

> **Note (v2.3.0+):** `embedding.dim` and `embedding.model` are
> compile-time fixed in `config/config.exs` and cannot be changed at
> runtime. Default: `jina-code-embeddings-1.5b-Q8_0` (1536-dim).
> The `external` setup wizard intentionally does NOT prompt for these
> because changing them requires a recompile.

## Per-command matrix (v2.5.0)

| Command       | Embedding | Chat  | `--llm-less` | `--with-explanation` | Failure mode if missing |
|---------------|-----------|-------|--------------|----------------------|----------------------------|
| `init`        | MUST*     | —     | n/a          | n/a                  | pre-flights embed server (auto-start) |
| `scan`        | **MUST**  | —     | n/a          | n/a                  | Every file's symbols get an embedding; failure breaks scan |
| `query`       | optional  | —     | `--llm-less` skips vector engine, falls back to BM25 + graph | n/a | `--llm-less` mode works without embeddings |
| `explain`     | —         | yes   | `--llm-less` skips LLM call, shows cached summary only | n/a | Without cached summary, prints hint to run `delfos summarize` |
| `summarize`   | **MUST**  | **MUST** | n/a (always LLM) | n/a | Iterates all symbols; calls embed + chat per symbol |
| `audit`       | —         | optional | `--llm-less` skips LLM narrative | `--with-explanation` adds LLM diagnosis | Without LLM, shows deterministic fallback |
| `graph`       | —         | —     | n/a          | n/a                  | Pure SQL; no LLM           |
| `mcp`         | **MUST**  | **MUST** | n/a | n/a | The MCP tools `search`, `lookup`, `context`, `explain` all hit LLM |
| `config`      | —         | —     | n/a          | n/a                  | Just edits the config file |
| `doctor`      | —         | —     | n/a          | n/a                  | Probes providers; degrades gracefully |
| `status`      | —         | —     | n/a          | n/a                  | DB count only             |
| `integrate`   | —         | —     | n/a          | n/a                  | Writes agent config files |
| `version`     | —         | —     | n/a          | n/a                  | — |

\* `init` triggers a full scan, so the scan's MUST applies. The
embed server is auto-started via `ensure_embedding_server/0` so the
scan can begin immediately.

## Removed in v2.x (history)

- `delfos thinker_*` config (v2.4.0) — folded into `[summarize]`
- `delfos watch` (v2.3.0) — merged into `delfos mcp`
- `delfos serve` (v2.3.0) — alias of `delfos mcp`
- `delfos context` (v2.3.0) — alias of `delfos agents`
- `delfos stadistics` (v2.3.0) — typo, use `delfos status --stats`
- `delfos preset`/`setup`/`models` (top-level) — use `delfos config <sub>`
- `delfos config wizard` (v2.3.0) — use `delfos config setup llm`
- `delfos agents <name>` (v2.3.0) — folded into `delfos explain`

## Categories

### MUST have LLM (5 commands)
`init` (via scan), `scan`, `summarize`, `mcp`, and `query` (by default).

### Optional LLM (3 commands)
`explain`, `audit`, `agents` — opt-in via `--with-explanation`. Without
it they show static info only.

### LLM-resilient (3 commands)
`query --llm-less`, `explain --llm-less`, `audit --llm-less` — skip
the LLM and use cached data or simpler algorithms (BM25 + graph,
deterministic fallback, etc.).

### No LLM at all
`graph`, `config`, `doctor`, `status`, `integrate`, `version`,
`watch` work without any LLM running.

## Operational rule of thumb

> If you run `llama-run embed` and `llama-run gpt_oss medium` in two
> terminals, every command works. With `--llm-less` flags you can
> still run `query`, `explain`, and `audit` if only the chat server
> is down.
>
> `delfos config setup llm` arranca los servers automáticamente
> cuando los detecta caídos (v2.4.0+). Usa `ensure_embedding_server/0`
> para el embed server y `ensure_running/0` para el chat.
>
> Para desarrollo manual: `llama-server -m <model> --port 9998
> --embedding ...` (embed) y `llama-server -m gpt-oss-20b-Q8_K_XL.gguf
> --port 9999 ...` (chat).

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
  },
  "summarize": {
    // Optional override (v2.4.0+). If present, Delfos prefers this
    // section for summarisation; falls back to [llm] otherwise.
    "url":      "http://127.0.0.1:9999",
    "model":    "gpt-oss",
    "max_tokens": 180
  },
  "models": {
    "gguf_dir": "/home/user/models/gguf"
  }
}
```

Use `delfos config set <section> <key> <value>` to edit without
hand-rolling JSON, or run `scripts/register-local-llms.sh` which does
the same end-to-end (writes a sensible local config for both
endpoints).

## Stale cloud provider auto-migration (v2.4.0+)

If `config.json` contains `provider: "openai"` or `provider:
"anthropic"` AND the URL is one of the wizard defaults
(`https://api.openai.com`, `https://api.anthropic.com`), Delfos
silently reverts the provider to `:local` and forces the local URL.
A `[Config] Detected stale openai config with default URL ...`
warning is logged so the user knows what happened.

Use `delfos config migrate-local` (v2.5.0) for the explicit version
of the same operation.

## LLM endpoint quirks handled in code (v2.4.0+)

- **Dim mismatch** (v2.4.0+, commit `d69e2f5`): the local
  jina-code server may return 1536-dim vectors instead of the
  configured 4096. `Delfos.LLM.CandilBridge.embed_batch/2` validates
  each vector against `compile_env(:delfos, :embedding)[:dim]` and
  returns `nil` for mismatches, with the warning logged ONCE per
  process lifetime via `:persistent_term`.
- **Response envelope** (v2.4.0+): the local gpt-oss server returns
  the full `%{content, role, finish_reason, ...}` envelope instead
  of just the text. `Delfos.LLM.Response.normalize/1` handles both
  shapes — used by `delfos explain` and `delfos summarize`.
- **Circuit breaker** (v2.4.0+, commit `4580849`): `Arrea.CircuitBreaker`
  wraps each Anthropic chat call. After N consecutive failures, the
  breaker opens and subsequent calls fail fast for a cool-down window.
