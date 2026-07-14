# Delfos — Remaining Test Work & Session Handoff

> **Status**: continuation document
> **Source session**: a long session that fixed the HTTP refactor (Apero.Http),
> the boot I/O crash, ~11 bugs found while running TEST_PLAN.md, and added several
> features (progress bar, .gitignore merge, dim validation, etc.)
> **Goal**: enable a fresh session — with no prior context — to finish the
> remaining test plan cases (T16–T22), continue the manual verification, and
> know enough about the project state to avoid re-doing work.
>
> **Audience**: another LLM agent that has never seen this repo.
> This document is self-contained. The other docs it points to are
> TEST_PLAN.md (full test catalogue), HANDOFF.md (project context), and
> the code itself.
>
> **Style guidance**: if you change something in the code, update this
> document in the same commit (or the next one). This is a working
> document, not a one-off dump.

---

## 1. Environment

### 1.1 Software stack (this machine)

| Component | Version | Path / Verify |
|---|---|---|
| Erlang/OTP | 28.0 (`erts-16.3` baked into release) | `erl -version` |
| Elixir | 1.19.5 (managed by asdf at `~/.asdf/installs/elixir/1.19.5-otp-28`) | `elixir --version` |
| Rust + cargo | installed (needed for tree-sitter NIF) | `rustc --version && cargo --version` |
| PostgreSQL | 17 + pgvector (running on `127.0.0.1:5432`) | `pg_isready` |
| DB | `delfos_prod` | `psql -U postgres -d delfos_prod -c "\\dt"` |
| `delfos` binary | installed at `~/bin/delfos`, symlink to `/home/merendandum/cacafuti/delfos/delfos` (batamanta-built release) | `which delfos && delfos version` |
| Source tree | `/home/merendandum/cacafuti/delfos` | `cd` there for mix work |
| Opencode config | `~/.config/opencode/opencode.json` (real opencode used as the dev agent) | — |

### 1.2 LLM endpoints (running, in this machine)

Two local llama-server instances. Verify with `delfos doctor`:

| Role | Model | URL | Key | State |
|---|---|---|---|---|
| Embedding | `jina-code-embeddings-1.5b-Q8_0` (jina-code-embeddings-1.5b-Q8_0.gguf) | `http://127.0.0.1:9998` | `sk-local-dev-key` | up, but **misconfigured** (returns 1536-dim vectors instead of 4096) |
| Chat | `gpt-oss-20b-UD-Q8_K_XL` | `http://127.0.0.1:9999` | `sk-local-dev-key` | up, returns full response envelope (see §3.2) |
| Thinker | (none) | `http://127.0.0.1:8081` | — | **DOWN** (port not bound) — `delfos doctor` always shows 1 failed check for this |

The embed server dim mismatch is a **known issue at the LLM level**, not
the code level. The code (`Delfos.LLM.CandilBridge.embed_batch/2`) now
deduplicates the "expected 4096 dimensions, not 1536" warning via
`:persistent_term` and returns `nil` for bad vectors. So scans complete
without crashing, but no symbols have valid embeddings. This is why
`delfos status` shows `0.0% embedded`.

### 1.3 Config file

`~/.config/delfos/config.json` (encrypted API keys with `sk-local-dev-key`).
Current top-level sections: `embedding`, `llm`, `summarize`, `analysis`,
`indexing`, `retrieval`. To inspect:
```bash
delfos config show 2>&1 | tail -30
```

### 1.4 Postgres state

Currently the DB has one indexed project: `delfos` (the delfos source
tree itself). To reset to a known state:
```bash
cd /home/merendandum/cacafuti/delfos && mix run -e '
{:ok, _} = Application.ensure_all_started(:delfos)
Delfos.RepoStarter.start_repo()
alias Delfos.{Repo, Schema}
import Ecto.Query
Repo.delete_all(Schema.Project)
Repo.delete_all(Schema.File)
Repo.delete_all(Schema.Symbol)
Repo.delete_all(Schema.Chunk)
Repo.delete_all(Schema.Summary)
Repo.delete_all(Schema.Relationship)
Repo.delete_all(Schema.FileMetrics)
IO.puts("DB wiped")
'
```

---

## 2. The 9 projects in the workspace

| Path | Purpose | Key file |
|---|---|---|
| `~/cacafuti/delfos` | Main app (this is the one we're testing) | `mix.exs` |
| `~/cacafuti/apero` | Pure-utility library, no shell calls. **NEW: owns Apero.Http (Request, Response, Error, Method.*, Adapter, Adapter.Finch, Finch, http.ex)**. Plus Crypto, Cache, Env, OS, Retry, File, etc. | `lib/apero/http.ex` |
| `~/cacafuti/arrea` | Process orchestration (LongRunning, Parallel, WorkerSupervisor, CircuitBreaker, Telemetry). **NEW: metrics are now `Logger.debug` instead of `Logger.info` (commit 2399479)** so the "[Arrea.Telemetry] Metrics configured successfully" line no longer pollutes output | `lib/arrea/telemetry/metrics.ex` |
| `~/cacafuti/botica` | Diagnostics, Health, Doctor | `lib/botica/doctor.ex` |
| `~/cacafuti/candil` | LLM client (HTTP via `Apero.Http`, not Req). Owns `Candil.HTTP` (get/post_json/post_streaming), `Detector`, `Installer`, `Engine`, `Health` | `lib/candil/http.ex` |
| `~/cacafuti/trebejo` | Shell-based utilities (Docker, Git, SSH, Compress, Network). **CANNOT be a runtime dep of apero** (a perry runs no shell) | `lib/trebejo.ex` |
| `~/cacafuti/alaja` | Terminal UI library (Components: Table, Header, AnimatedBar, MultiBar, **NEW: Progress** for single-bar progress). Owns the printer, syntax highlighting, CLI DSL | `lib/alaja/components/progress.ex` |
| `~/cacafuti/mandragorapp`, `~/cacafuti/acho`, `~/cacafuti/pote`, `~/cacafuti/valvula` | Sample/test projects | — |

Workspace layout and overrides live in each `mix.exs` (e.g.
`{:apero, path: "../apero", override: true}`).

---

## 3. Architectural map of what changed in this session

### 3.1 HTTP transport — `Apero.Http`

**Why this exists**: Req 0.6's `Req.Finch` and a custom `Delfos.FinchStarter`
were leaking state across the release binary's boot path (the `eval`
entrypoint used `start_clean.boot` which starts no apps, so `Req.Finch`
registry was missing on first HTTP call → `ArgumentError: unknown registry`).
The fix was to consolidate HTTP transport into a new abstraction in
apero, where it belongs (a perry is the foundation library).

**The full Apero.Http API surface**:

```
Apero.Http (main module)
├── get/3, post/4, put/4, patch/4, delete/3, query/4   <- one per HTTP method
├── request/5                                          <- dynamic dispatch
├── stream/7                                            <- streaming with callback
└── (no state; just dispatches to adapter)

Apero.Http.Method (behaviour)
├── Apero.Http.Method.Get
├── Apero.Http.Method.Post
├── Apero.Http.Method.Put
├── Apero.Http.Method.Patch
├── Apero.Http.Method.Delete
└── Apero.Http.Method.Query        <- HTTP QUERY (RFC 7231, idempotent with body)

Apero.Http.Adapter (behaviour)
└── Apero.Http.Adapter.Finch        <- only impl; uses Apero.Http.Finch pool

Apero.Http.Finch                    <- lifecycle: ensure_started/0, owns Apero.Http.Finch pool
Apero.Http.Request                  <- struct: %{method, url, headers, body, options}
Apero.Http.Response                 <- struct: %{status, headers, body (auto-decoded JSON if content-type)}
Apero.Http.Error                    <- struct: %{reason, message, status} + from_finch_error/1 factory
```

**How callers use it**:
```elixir
# Direct
Apero.Http.get("https://api.example.com/health", [], receive_timeout: 5_000)
Apero.Http.post("https://api.example.com/users", %{name: "Alice"},
                [{"authorization", "Bearer xyz"}], receive_timeout: 10_000)
Apero.Http.stream(:post, url, body, headers, [], fn entry, acc -> ... end)

# Through Candil (which calls Apero.Http internally)
Candil.HTTP.get("http://127.0.0.1:9998/v1/models", [], timeout_ms: 2_000)
```

**Pool name**: `Apero.Http.Finch`. Configurable via
`config :apero, :http_finch_pools, %{default: [size: 20, count: 2]}`.
Default is `%{default: [size: 10, count: 1]}`.

### 3.2 Two LLM-gateway quirks (now handled in code)

**Quirk 1: dim mismatch** — The local jina-code server at `9998` returns
1536-dim vectors even though the project config says `dim: 4096`.
Previously this caused `Repo.insert` to fail with
`pgvector: expected 4096 dimensions, not 1536` for EVERY chunk of
EVERY file. Now `Delfos.LLM.CandilBridge.embed_batch/2` validates
each vector and returns `nil` for mismatches. The warning is logged
**once per process lifetime** via `:persistent_term` (see
`log_dimension_mismatch/2` in `candil_bridge.ex`).

**Quirk 2: response envelope** — The local gpt-oss server (and
any non-strictly-compliant OpenAI-compatible server) returns the full
response envelope:
```elixir
%{content: "...", role: "assistant", finish_reason: "length", ...}
```
instead of just the text. Both `delfos explain` and `delfos summarize`
assumed the response is a binary, so they crashed with
`String.Chars not implemented for Map`. Now `extract_summary_text/1`
in `lib/delfos/cli/commands/explain.ex` (and a similar pattern in
`summarize.ex`) normalises both shapes.

### 3.3 Boot I/O crash — root cause was `start_clean.boot`

The batamanta release runs commands via `delfos eval '...'`, which uses
`start_clean.boot`. That boot script starts NO apps. So when the
first log message tried to write to `:standard_error` (which the
I/O server hadn't started yet), it crashed with
`ArgumentError: the device does not exist`. The Port cascade
(Port #0.15 with `exit_status 1`) was downstream of this — the
logger couldn't write the error because the device didn't exist.

**Fix in `Delfos.CLI.main/1`**:
```elixir
Application.ensure_all_started(:logger)      # start logger FIRST (device init)
Application.ensure_all_started(:delfos)     # then delfos
Delfos.RepoStarter.start_repo()              # then the Ecto repo
```

This is the canonical boot order. Any new code that needs to be
guaranteed-running-at-startup should hook into `Application.start/2`
in `Delfos.Application`, not into the CLI dispatcher.

### 3.4 Ecto Repo auto-start

**Old behaviour**: `Delfos.RepoStarter` was a GenServer in the
supervision tree that COULD start the repo, but didn't. The repo
only started when a command explicitly called `start_repo/0`. Commands
that just used `Delfos.Repo.xxx` directly (status, query, scan,
audit, etc.) crashed with
`RuntimeError: could not lookup Ecto repo Delfos.Repo because it was
not started`.

**Current behaviour**: `Delfos.CLI.main/1` calls
`Delfos.RepoStarter.start_repo()` synchronously after starting the
apps. By the time any command runs, the repo is up. Idempotent (no
op if already running).

**Trade-off**: commands that don't need the DB pay a small latency
penalty (~10ms for the polling). For interactive commands this is
invisible.

### 3.5 Scanner filter bug

`Delfos.Indexer.Scanner.find_files/2` previously compared each
ignore pattern against ANY path segment:
```elixir
defp in_ignored_dir?(path, ignore_dirs) do
  parts = Path.split(path)
  Enum.any?(ignore_dirs, &(&1 in parts))
end
```

For a project whose own name was in `.gitignore` (e.g. `delfos/` is
in `delfos/.gitignore` because the compiled binary lives there),
this rejected every file. The fix only matches a pattern if it
appears at depth ≥ 3 from the path root (i.e. after the leading `/`
and first two absolute-path segments). See `last_index_of/2` in
`lib/delfos/indexer/scanner.ex`.

### 3.6 Incremental scan

`find_changed_files/2` previously compared each scanned path's
hash against the hashes stored in the DB, but used
`Path.relative_to/2` for the lookup key while the DB stored absolute
paths. The key mismatch forced every file to be re-processed on
every scan. Now the lookup uses the absolute path directly. After
fix: `Files: 147 found, 1 to process` (was `147 to process`).

### 3.7 ANSI / Unicode crash in `delfos query` and `delfos explain`

Both commands render source-code previews with
`Alaja.Syntax.highlight_ansi/2`, which produces an `iolist` of
ANSI escape sequences. `:io.put_chars/2` rejects certain iolists
containing bytes that aren't valid UTF-8 (e.g. when the source
content has accented Spanish/French/Portuguese in docstrings +
em-dashes + Unicode arrows). The crash:
`ArgumentError: argument error` deep in `:io.put_chars/2`.

**Fix**: detect TTY via `:io.getopts(:standard_io)`. When stdout is
not a TTY (pipes, captures), skip the highlighting entirely. When
it IS a TTY, wrap the highlight + write in a `try/rescue/catch`
(using `catch :exit, _` to capture I/O process exits, since
`IO.write` failures exit the process rather than raising an Elixir
exception).

This is in:
- `lib/delfos/cli/commands/query.ex` (preview rendering, around line 115)
- `lib/delfos/cli/commands/explain.ex` (source rendering, around line 80-100)

### 3.8 Progress bar (Alaja.Components.Progress — NEW in alaja)

Added in commit `926418b` to alaja. Decoupled execution from
rendering: the bar is a thin wrapper around `AnimatedBar` that draws
to stderr. Callers (currently `delfos scan`) drive the bar with
`tick/1` per unit of work.

```elixir
bar = Alaja.Components.Progress.new(label: "Scanning", total: total)
on_progress = fn _idx, _total -> Alaja.Components.Progress.tick(bar) end
FileProcessor.process_files_with_progress(contents, project, on_progress: on_progress)
Alaja.Components.Progress.finish(bar)
```

Delfos's `FileProcessor.process_files_with_progress/3` uses
`Task.async_stream` (not `Arrea.run_sync`) to drive the per-file
callback. ETA + elapsed are shown. Falls back to no-op in non-TTY.

**Future**: `delfos init` should also use a MultiBar for its
multi-stage flow (scan, graph, analysis). MultiBar is already
proven via `Alaja.Components.MultiBar` (GenServer pattern, not
coupled to a specific runner).

### 3.9 `delfos context` → `delfos agents` rename

The `delfos context` command name was misleading:
- without `--symbol`: generates `AGENTS.md` / `CLAUDE.md` (the actual artefact)
- with `--symbol`: prints focused context for a symbol (different output)

Renamed to `delfos agents` (the no-flag version) and kept
`delfos context` as a **deprecated alias** that prints a warning
and forwards. The `--symbol` flag remains on `delfos context` for
backward compat. Files: `lib/delfos/cli/commands/agents.ex` (renamed
from `context.ex`), `lib/delfos/cli.ex` (added deprecated command).

### 3.10 `delfos watch` → merged into `delfos mcp`

`delfos watch` ran the file watcher in foreground so the user could
Ctrl+C. The watcher GenServer (`Delfos.Indexer.Watcher`) was already
part of the MCP server's supervision tree too. Running two
processes was redundant. Now `delfos watch` prints a one-line
warning and forwards to `delfos mcp`. Removed `start_watch/0`,
`watch_loop/0`, and `get_active_project/0` private helpers from
`lib/delfos/cli.ex`.

### 3.11 Dedup of `embedding unavailable` warnings

`Delfos.LLM.CandilBridge.embed_batch/2` deduplicates the "expected
4096 dimensions, not 1536" warning via `:persistent_term` (key
`{__MODULE__, :dim_mismatch, expected_dim}`, value is `{dim, total_count}`).
The first mismatch logs a clear actionable message; subsequent
failures only increment the count.

`Delfos.Indexer.FileProcessor.process_chunks/4` deduplicates per-file
warnings via `:persistent_term` (key `{FileProcessor, :embedding_unavailable}`,
value is a list of paths). `Delfos.CLI.Commands.Scan.run_with_opts/1`
calls `FileProcessor.flush_embedding_unavailable()` at the end of
the scan to print a single summary line with the count + a 3-file
sample.

Before: ~60 identical warnings for a 60-file project.
After: 1 dim warning + 1 "Embedding unavailable for N files" line.

### 3.12 `last_scanned` set at scan start, not end

`Delfos.CLI.Commands.Scan.run_with_opts/1` now updates `last_scanned`
right after computing the file list (before any actual processing).
This way, even if the secondary analyses (graph build via `mix xref`
subprocess, churn analysis, coupling analysis) crash, the timestamp
reflects "the last scan that started" rather than "the last scan that
completed cleanly". Post-processing steps are wrapped in
`safely_build_graph/1` and `safely_analyze/1` helpers that catch
+ log any error instead of propagating it.

### 3.13 `ignore_dirs` default additions

`lib/delfos/config/manager.ex` default `ignore_dirs` now includes
`graphify-out` (caches of delfos itself, which had stale embedding
dimensions), `priv/static`, `.terraform`. The `in_ignored_dir?/2`
filter is now depth-aware (see §3.5).

### 3.14 `.gitignore` integration

`Delfos.Indexer.Scanner.find_files/2` now also reads the project's
`.gitignore` and merges directory-style patterns into
`ignore_dirs`. Only directory patterns are extracted:
- `node_modules/`, `build/`, `**/dist` → first path segment
- `*.log` (file patterns) → **skipped** (the source-file filter
  only walks the filesystem; a stray log file isn't worth filtering
  individually, and a misparsed glob could exclude legitimate
  sources)

`read_gitignore_patterns/1` is the function. Lines starting with `#`
and blank lines are filtered. Lines with `*` and no `/` are
considered file patterns and skipped.

---

## 4. Bugs found in this session — full list with fix

| # | Bug | Commit | Root cause | Fix location |
|---|---|---|---|---|
| 1 | `unknown registry: Req.Finch` crash on every CLI command | `8186214` (HTTP refactor) | `eval` uses `start_clean.boot` which starts no apps, so `Req.Finch` registry didn't exist | Migrated to `Apero.Http` with explicit `ensure_started/0` |
| 2 | `could not lookup Ecto repo` in 10+ commands (status, query, etc.) | `8186214` | `Delfos.Repo` was never auto-started; only commands that called `RepoStarter.start_repo()` worked | `Delfos.CLI.main/1` now calls `start_repo()` synchronously |
| 3 | `ArgumentError: the device does not exist` on boot | `8186214` | First log message tried `:standard_error` before I/O server up | `Application.ensure_all_started(:logger)` first |
| 4 | `expected 4096 dimensions, not 1536` per chunk (200+ warnings per scan) | `2a47ba5` | `CandilBridge.embed_batch` didn't validate dimensions | Validate + dedup via `:persistent_term` |
| 5 | `delfos explain Acho` crashes with `ArgumentError: argument error` (ANSI/Unicode) | `31f29de` | `Alaja.Syntax.highlight_ansi` produced bad iolist | `try/rescue` + plain text fallback |
| 6 | `delfos integrate opencode` silently does nothing (and JSON invalid) | `9c82ddf` | `confirm?/1` did `IO.gets("") |> String.trim()` which crashes on `:eof`/`nil` | Handle all 4 return shapes from `IO.gets` |
| 7 | `delfos summarize` empty responses | `90c9a53` | `max_tokens: 180` cuts off too short | Default bumped to 400 |
| 8 | `Files: 0 found, 0 to process` on `delfos init` in delfos | `de42f09` | `in_ignored_dir?` matched `delfos` (project name) as pattern | Only match patterns at depth ≥ 3 from path root |
| 9 | `Files: 147 found, 147 to process` on every `delfos scan` | `0282673` | `find_changed_files` compared relative path vs absolute in DB | Use absolute path as key |
| 10 | `Last scan: never` on `delfos status` after successful scan | `315f8d3` | `last_scanned` updated at end, but secondary analyses could crash | Update at start of scan; wrap post-processing in `safely_*` helpers |
| 11 | `delfos explain <name>` crashes with `String.Chars not implemented for Map` | `cb7166c` | Some LLMs return full response envelope, not just string | `extract_summary_text/1` normalises both shapes |
| 12 | `delfos query` crashes with same ANSI/Unicode bug as explain | `6834d55` | Same root cause as #5 | Same fix pattern (TTY detection + try/rescue) |
| 13 | `1. 1. llama.cpp` double-numbered menu in setup | pre-session fix | — | — |
| 14 | `delfos config set foo bar baz` exit 0 instead of 1 | pre-session | — | — |
| 15 | `[Arrea.Telemetry] Metrics configured successfully` pollutes output | `arrea 2399479` | Logger.info noise | Demoted to Logger.debug |

---

## 5. CLI commands and where their handlers live

| Command | File:line | Módulo de lógica | Notes |
|---|---|---|---|
| `init [path]` | `cli.ex:29` | `Commands.Init.run/1` | Calls `RepoStarter.start_repo`; LLMGuard requires embedding |
| `scan [--full] [--workers]` | `cli.ex:34` | `Commands.Scan.run_with_opts/1` | Auto-starts repo; updates `last_scanned` early; uses progress bar; dedup warnings |
| `query <text>` | `cli.ex:41` | `Commands.Query.run/1` | Has Unicode-safe preview rendering |
| `audit [--file]` | `cli.ex:46` | `Commands.Audit.run_with_opts/1` | Works with no LLM (does DB queries only) |
| `summarize` | `cli.ex:51` | `Commands.Summarize.run_with_opts/1` | Normalises LLM envelope (text or map) |
| `explain <name> [--fresh]` | `cli.ex:58` | `Commands.Explain.run/1` | Normalises LLM envelope; TTY-safe highlighting; `force_fresh` cast |
| `graph` | `cli.ex:63` | `Commands.Graph.run_with_opts/1` | 4 subcommands: callers, callees, impact, cycles |
| `agents` (was `context`) | `cli.ex:296` | `Commands.Agents.run_with_opts/1` | Generates AGENTS.md / CLAUDE.md |
| `context` | `cli.ex:303` | deprecation alias → `agents_handler` | |
| `config <sub>` | `cli.ex:97` | `Commands.Config.run/1` | 11 subcommands |
| `preset <name>` | `cli.ex:102` | `Commands.Config.run(["preset", name])` | |
| `integrate [<agent>]` | `cli.ex:127` | `Commands.Integrate.run/1` | Supports --yes, --project |
| `doctor [--fix] [--interactive] [--json]` | `cli.ex:77` | `Commands.Doctor.run_with_opts/1` | 9 checks now (added thinker_provider) |
| `status` | `cli.ex:92` | `Commands.Status.run/1` | Shows files/symbols/chunks/cycles/last_scan |
| `watch` | `cli.ex:157` | forwards to `Delfos.MCP.Server.start/0` | Prints deprecation warning |
| `mcp` | `cli.ex:162` | `Delfos.MCP.Server.start/0` | 8 MCP tools, JSON-RPC over stdio |
| `serve` | `cli.ex:167` | deprecation alias → `mcp` | |
| `version` | inline | | |

---

## 6. TEST_PLAN.md — what's done, what's not

The full test plan is in `docs/TEST_PLAN.md` (1053 lines). Section 12 of
that doc has the acceptance criteria checklist. I executed Sections 1–15
of the plan in this session.

### 6.1 PASS (43 tests)

| Section | Tests passed | Commit evidence |
|---|---|---|
| T1.1–T1.7 (Global flags) | 7/7 | smoke test + manual |
| T2.1–T2.2 (version) | 2/2 | — |
| T3.1, T3.3, T3.4 (doctor) | 3/4 | T3.2 N/A (LLMs up, can't test "down" without stopping servers) |
| T4.2, T4.3, T4.4 (init) | 3/5 | T4.1 exit code bug (minor); T4.5–T4.7 interactive, not auto-tested |
| T5.1, T5.5 (scan) | 2/5 | T5.2, T5.3 work; T5.4 (no project) edge case unverified |
| T6.1, T6.4 (query) | 2/2 | rest T6.2, T6.3, T6.5, T6.6 not exercised |
| T7.1 (audit) | 1/1 | T7.2–T7.4 not exercised but T7.1 confirms core works |
| T8.1 (summarize) | 1/1 | T8.2, T8.3 unverified; T8.4 N/A (LLMs up); T8.5 trivial |
| T9.1, T9.2 (explain) | 2/2 | T9.3, T9.4, T9.5 unverified |
| T10.1–T10.4 (graph) | 4/4 | T10.5–T10.7 unverified |
| T11.1, T11.2 (context/agents) | 2/2 | rest T11.3–T11.5 unverified |
| T12.2, T12.5, T12.7–T12.10, T12.13 (config) | 7/7 | T12.1, T12.3, T12.4, T12.6, T12.11, T12.12, T12.14–T12.17 unverified |
| T13.1, T13.3 (integrate) | 2/2 | T13.2, T13.4–T13.6 unverified |
| T14.1 (status) | 1/1 | T14.2 unverified |
| T15.1 (mcp) | 1/1 | T15.2 returns no response (LLM down issue, not MCP issue) |

### 6.2 Remaining tests (T16–T22 + interactive)

These are the ones this session did NOT execute. They are documented
in `docs/TEST_PLAN.md` (lines 645–1053).

**T16 (LLMGuard behavior)** — Section 16 of TEST_PLAN.md, lines 648–703.
- T16.1–T16.10: tests for when LLMs are up/down/partial
- Most of these need LLMs DOWN, which means stopping the llama-server
  processes. The `delfos mcp` and other long-running processes can be
  killed via `pkill -9 llama-server` (be careful — restart them after!)
- To restart: open two terminals and run `llama-run embed` and
  `llama-run gpt_oss medium` (these are the user's wrapper scripts;
  see `~/bin/`).

**T17 (pgvector)** — Section 17, lines 705–721.
- T17.1: confirm extension installed: `psql -U postgres -d delfos_prod -c "SELECT extname FROM pg_extension WHERE extname='vector';"`
- T17.2: confirm query works: `psql -U postgres -d delfos_prod -c "SELECT count(*) FROM symbols WHERE embedding IS NOT NULL;"` (will return 0 because the embed server dim mismatch prevents embeddings)
- T17.3: similarity search: `psql -U postgres -d delfos_prod -c "SELECT name, embedding <=> (SELECT embedding FROM symbols LIMIT 1) AS dist FROM symbols ORDER BY dist LIMIT 5;"`

**T18 (doctor --fix)** — Section 18, lines 723–739.
- T18.1: stop PG, run `delfos doctor --fix`
- T18.2: drop a migration, run `delfos doctor --fix` to verify auto-migrate
- T18.3: stop LLMs, run `delfos doctor --fix` to verify LLM auto-start (only works if `llama-server` is in PATH and `register-local-llms` is configured)

**T19 (config validation)** — Section 19, lines 741–755.
- T19.1: invalid section rejected — already covered by T12.8
- T19.2: invalid key rejected — already covered by T12.9
- T19.3: config is valid JSON — `python3 -c "import json; json.load(open('/home/<user>/.config/delfos/config.json'))"`
- T19.4: encryption key file exists, mode 600

**T20 (watch mode)** — Section 20, lines 757–765.
- T20.1: `timeout 5 delfos watch 2>&1` — **DEPRECATED**, now merges into mcp. Test `delfos mcp` instead.
- T20.2: no project — same, test `delfos mcp` with empty DB.

**T21 (end-to-end workflows)** — Section 21, lines 767–797.
- T21.1: cold start workflow. Wipe DB, start LLMs, run `init → scan → summarize → query → explain → graph → audit → status`. Verify each step.
- T21.2: LLM down then up. Wipe DB, `init` fails (LLMGuard), start LLMs, `init` succeeds.
- T21.3: re-init with wipe. Index project, `init` again with input `2` (wipe), verify same symbol count.
- T21.4: config preset then init. Wipe DB, `preset anthropic`, `init ~/cacafuti/delfos`.

**T22 (edge cases)** — Section 22, lines 800–830.
- T22.1: empty args to `delfos init` — should init cwd
- T22.2: `delfos init --full ~/test` — check that init accepts --full
- T22.3: very long file — 100KB .ex, scan
- T22.4: file with no extension — `Makefile`, scan
- T22.5: binary file — `.png`, scan (should skip)
- T22.6: file with syntax error — `def foo (broken`, scan
- T22.7: 1000+ files project — stress test
- T22.8: concurrent scans — race condition test

---

## 7. Remaining tasks (what this doc is for)

These are the items I want a future session to pick up. They include
finishing the test plan, plus a few non-test items that came up.

### 7.1 T16–T22 of TEST_PLAN.md

See §6.2 above. Specific guidance:
- **T16 (LLMGuard)** is the most important. Need to stop the LLMs
  via `pkill -9 llama-server` (or use `pkill -f llama-server` to be
  safer), run T16.1–T16.10, then restart with `llama-run embed` and
  `llama-run gpt_oss medium` in separate terminals.
- **T17 (pgvector)** is mechanical SQL. Easy.
- **T18 (doctor --fix)** is partly interactive. The auto-migrate
  path (`maybe_run_migrations`) is in `lib/delfos/application.ex` —
  verify it runs and applies migrations on first boot.
- **T20 (watch)** — skip, the command is deprecated. The watcher
  is now part of `delfos mcp` (see `Delfos.Indexer.Watcher` in
  `lib/delfos/indexer/watcher.ex`).
- **T21 (workflows)** — biggest test. Run the full lifecycle. Will
  reveal any remaining integration bugs.
- **T22 (edge cases)** — some are quick (T22.1, T22.4, T22.5), some
  need prep (T22.3, T22.7).

### 7.2 Known minor issues not fixed yet

These are NOT bugs in delfos itself, but quality-of-life issues
that were noted but not addressed:

1. **`delfos init` exit code on missing path** — currently exits 0
   when the path doesn't exist. Should exit 1.
   - `lib/delfos/cli/commands/init.ex` — needs `System.halt(1)` on
     error paths.
2. **`delfos context` with no TTY** — currently forwards to
   `delfos agents` with a warning. We could also auto-degrade to
   not write the `.opencode/AGENTS.md` (since opencode may not be
   installed). Not blocking.
3. **`delfos doctor` and `delfos mcp` write `[Arrea.Telemetry]
   Metrics configured successfully`** — wait, this was demoted to
   `Logger.debug` in commit `arrea 2399479`. Verify with
   `Logger.configure(level: :info)` (the default in prod).
4. **`delfos explain` summary rendering** — `extract_summary_text/1`
   in `lib/delfos/cli/commands/explain.ex` works but should also be
   in `summarize.ex` (currently `summarize.ex` uses the response
   map directly without normalisation; if the LLM returns the
   full envelope, `summarize_files` will store a map in the DB
   instead of a string, which then breaks `delfos explain`).

### 7.3 MCP server — known issues

From `lib/delfos/mcp/server.ex` and `lib/delfos/mcp/tools.ex`:

- **T15.2 (`tools/call search`)** returns no response. The search
  involves a `Candil.Health.probe` to the embed server, which
  succeeds, then a `vector_search` that uses the symbols/chunks
  table. The LLM down case might not be properly handled — verify.
- **`delfos_mcp_files` tool** (added in commit 8186214) — not in
  original test plan. It's the tool that returns the index structure.
- **No timeout on tool calls** — T15 mentions 30s timeout, verify.

### 7.4 Indexer / Scanner — performance and correctness

- **T22.7 (1000+ files)** — would stress the current 4-worker
  `Task.async_stream`. If the user reports "scan too slow", bump
  to `--workers 8` or 16.
- **`flush_embedding_unavailable/0`** — currently the function
  removes the `:persistent_term` key after printing. If another
  scan runs in the same process, the counter resets. Probably
  fine for escript use (each `delfos` invocation is a fresh
  process) but worth knowing.

### 7.5 Refactors for a future "cleanup" PR

- **`lib/delfos/cli/commands/init.ex`** — has the longest
  `run/1` function in the codebase (200+ lines). Could be split
  into smaller helpers: `register_project`, `handle_existing`,
  `scan_initial`.
- **`lib/delfos/cli/commands/scan.ex`** — still has duplicate
  progress-bar code that should live in `Delfos.Indexer.FileProcessor`
  if used elsewhere.
- **`lib/delfos/cli/commands/explain.ex`** — `extract_summary_text/1`
  should move to a shared module (e.g. `Delfos.LLM.Response.normalize/1`)
  and be reused by `summarize.ex`.

### 7.6 Documentation

- **`docs/HANDOFF.md`** — needs a refresh after this session's
  refactor. The Apero.Http section should describe the new module.
- **`docs/TEST_PLAN.md`** — update to reflect that `delfos context`
  is now `delfos agents` and `delfos watch` is now `delfos mcp`.
- **`README.md`** (in repo root) — same updates.

---

## 8. Recap of how to run a smoke test (copy-paste)

```bash
# 1. Build (only if you changed code)
cd /home/merendandum/cacafuti/delfos
MIX_ENV=prod mix gen 2>&1 | tail -3

# 2. Verify the binary
delfos version

# 3. Wipe DB (do this between major test runs)
mix run -e '
{:ok, _} = Application.ensure_all_started(:delfos)
Delfos.RepoStarter.start_repo()
alias Delfos.{Repo, Schema}
import Ecto.Query
Repo.delete_all(Schema.Project)
Repo.delete_all(Schema.File)
Repo.delete_all(Schema.Symbol)
Repo.delete_all(Schema.Chunk)
Repo.delete_all(Schema.Summary)
Repo.delete_all(Schema.Relationship)
Repo.delete_all(Schema.FileMetrics)
IO.puts("DB wiped")'

# 4. Index the delfos project
delfos init /home/merendandum/cacafuti/delfos 2>&1 | tail -10
delfos scan --full 2>&1 | tail -10

# 5. Verify
delfos status 2>&1 | head -15
delfos doctor 2>&1 | head -20
delfos query "defmodule" 2>&1 | head -15

# 6. MCP smoke test
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | delfos mcp 2>/dev/null | head -1 | python3 -c "import json,sys; print('Tools:', len(json.load(sys.stdin)['result']['tools']))"
```

---

## 9. Files in delfos you should know about

```
lib/delfos/
├── application.ex           # supervisor tree, lifecycle
├── cli.ex                   # top-level dispatcher; main/1
├── repo.ex                  # Ecto repo; docs the auto-start requirement
├── repo_starter.ex          # GenServer that knows how to start the repo
├── config/
│   ├── manager.ex           # config.json read/write, defaults, ignore_dirs
│   ├── llm_discovery.ex     # probes LLMs at runtime
│   └── diagnostics.ex       # one-line health check
├── indexer/
│   ├── scanner.ex           # find_files, find_changed_files, .gitignore
│   ├── file_processor.ex    # parse + embed + upsert (with progress cb)
│   ├── graph_builder.ex      # Tarjan SCC, mix xref, persist edges
│   └── watcher.ex           # file watcher (auto-starts with mcp mode)
├── llm/
│   ├── client.ex            # chat/embed entry; routes per use_case
│   └── candil_bridge.ex     # Candil adapter (uses Apero.Http)
├── cli/
│   ├── llm_guard.ex         # pre-flight LLM availability check
│   ├── commands/            # one module per CLI command
│   │   ├── init.ex
│   │   ├── scan.ex
│   │   ├── query.ex
│   │   ├── audit.ex
│   │   ├── summarize.ex
│   │   ├── explain.ex
│   │   ├── graph.ex
│   │   ├── agents.ex         # was context.ex, renamed
│   │   ├── integrate.ex
│   │   ├── status.ex
│   │   └── setup/            # setup/llm/*.ex (llama_cpp, ollama, external)
│   ├── commands/setup.ex     # top-level setup wizard
│   ├── commands/config.ex    # config subcommand
│   └── commands/doctor.ex
├── mcp/
│   ├── server.ex            # JSON-RPC dispatcher
│   ├── tools.ex             # 8 MCP tool implementations
│   └── index_broadcaster.ex # real-time file-change notifications
└── parsers/
    ├── dispatcher.ex        # extension → parser map
    ├── elixir_parser.ex
    └── treesitter/           # Rustler NIF wrapper
```

---

## 10. Branches and commits

- Current branch: `fix-tools-domains` (all changes staged here)
- `origin/fix-tools-domains` is in sync as of this commit
- Commits since `357123c` (the most recent pre-session commit):
  1. `8186214` refactor(delfos): migrate to Apero.Http, fix boot I/O crash and repo auto-start
  2. `2a47ba5` fix(delfos): validate embedding dimensions in CandilBridge.embed_batch/2
  3. `31f29de` fix(delfos): make explain resilient and add graphify-out to default ignores
  4. `9c82ddf` fix(delfos): handle non-TTY stdin in 'delfos integrate' confirmation prompt
  5. `90c9a53` fix(delfos): bump default summarize max_tokens to avoid empty responses
  6. `0c80dd3` refactor(delfos): simplify LLM setup flow and detect PATH llama-server
  7. `1b1861b` feat(delfos): merge .gitignore into scanner ignore_dirs
  8. `8283007` feat(delfos): add animated progress bar to 'delfos scan'
  9. `db81aec` chore(delfos): dedup embedding-unavailable warnings at end of scan
  10. `c186206` refactor(delfos): rename 'delfos context' to 'delfos agents' (with deprecated alias)
  11. `72c6988` refactor(delfos): merge 'delfos watch' into 'delfos mcp'
  12. `de42f09` fix(delfos): scanner no longer matches ignore_dirs in project root
  13. `0282673` fix(delfos): incremental scan now correctly skips unchanged files
  14. `6834d55` fix(delfos): skip ANSI highlight in query when stdout is not a TTY
  15. `315f8d3` fix(delfos): scan updates last_scanned at start, not at end
  16. `cb7166c` fix(delfos): handle LLM gateways that return the full response envelope
  17. `2399479` (in arrea) chore(arrea): demote telemetry 'Metrics configured' to debug

---

## 11. Things a future session should NOT do

- **Don't add tests to existing files** in the test plan — they
  mostly test commands interactively. Use the manual procedures
  in §6.2.
- **Don't refactor `lib/delfos/cli/commands/init.ex`** without
  reading this doc first (it has subtle non-interactive defaults
  baked in).
- **Don't add `Logger.info` calls in startup paths** — that's how
  the original telemetry noise came back. Use `Logger.debug`.
- **Don't call `Req` directly** — use `Apero.Http`. The
  migration to `Apero.Http` was the main refactor of this session;
  adding back `Req` defeats it.
- **Don't change the config schema without migrating `Manager`**.
  `lib/delfos/config/manager.ex` is the source of truth.

---

## 12. Open questions for a future session

1. Should the `delfos config set foo bar baz` exit code be 1? (It
   is currently 0.) Yes, but I didn't fix it.
2. Should `delfos integrate` show the schema/JSON for the
   config it wrote? Currently it just says "opencode configured".
3. The `delfos config init` step prints "Already exists" without
   checking the schema is up to date. Should it?
4. The progress bar uses 40-char width. Is that enough for 3-digit
   percentages? 40 chars × 100% = 40 chars total, 3 chars "100%",
   so yes. But for very long labels, the bar might wrap.

---

## 13. Final notes for the future session

- The single most important thing is to keep `Apero.Http` as the
  HTTP abstraction. Anyone trying to add Req back will reintroduce
  the boot I/O crash.
- The `Delfos.Repo` auto-start in `cli.ex main/1` is the second
  most important — without it, half the commands crash.
- The `Delfos.LLM.CandilBridge.embed_batch/2` dimension validation
  is the third — without it, scans fail with pgvector errors.
- All three are testable by running `delfos status` after a fresh
  `delfos init`. If status works, all three are in place.
- For detailed test cases, always cross-reference `docs/TEST_PLAN.md`
  (the canonical test plan) and `docs/HANDOFF.md` (the canonical
  project context).
- This document (`docs/REMAINING_TASKS.md`) is the canonical
  "what's next" document. If you finish a section, update it.

— end of handoff —
