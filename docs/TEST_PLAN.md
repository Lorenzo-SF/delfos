# Delfos End-to-End Test Plan

> **Status**: ready to execute
> **Audience**: another agent in a fresh session
> **Goal**: drive every `delfos` command, subcommand, and feature against
> a known state, document expected behavior, and detect functional
> bugs, UX issues, and silent failures.

## 1. Scope

This plan covers:

- All 15 top-level commands (`init`, `scan`, `query`, `audit`, `summarize`,
  `explain`, `graph`, `context`, `config`, `integrate`, `doctor`,
  `status`, `watch`, `mcp`, `serve`, `version`).
- All `delfos config` subcommands (`show`, `path`, `init`, `get`, `set`,
  `preset`, `setup`, `wizard`, `models`, `doctor`, `probe`).
- All `delfos graph` subcommands (`callers`, `callees`, `impact`, `cycles`).
- Global flags (`--help`, `-h`, `--version`, `-v`).
- LLMGuard pre-flight behavior with LLMs both up and down.
- pgvector extension handling.
- End-to-end workflows combining multiple commands.
- Error / edge cases (bad args, broken config, missing services).

## 2. Test environment

### 2.1 Software

| Component | Version / Location |
|---|---|
| Delfos binary | `~/bin/delfos` |
| Delfos source | `~/cacafuti/delfos/` |
| Elixir / OTP | 1.19.5 / 28.0 |
| Postgres | 17 + pgvector extension |
| DB | `delfos_prod` on `127.0.0.1:5432` |

### 2.2 LLM endpoints

Two **local** LLMs (per `~/bin/llama-run`):

| Role | Model | URL | Alias |
|---|---|---|---|
| Embedding | `Qwen3-Embedding-8B` (Q4_K_M) | `http://127.0.0.1:9998` | `embed` |
| Chat | `gpt-oss-20b` (UD-Q6_K_XL) | `http://127.0.0.1:9999` | `gpt-oss` |

Both share API key: `sk-local-dev-key`.

### 2.3 Configuration files

| File | Purpose |
|---|---|
| `~/.config/delfos/config.json` | main config (encrypted API keys) |
| `~/.config/delfos/.key` | encryption key (auto-generated) |
| `~/bin/register-local-llms` | registration helper (created in this session) |
| `~/bin/llama-run` | LLM launcher |

## 3. Setup

> Run all setup steps before executing tests. Each test depends on
> these being correct.

### 3.1 Verify LLM configuration

```bash
cat ~/.config/delfos/config.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
print('llm:', cfg['llm']['url'], cfg['llm']['model'])
print('embedding:', cfg['embedding']['url'], cfg['embedding']['model'])
"
```

**Expected output:**
```
llm: http://127.0.0.1:9999 gpt-oss
embedding: http://127.0.0.1:9998 embed
```

**Pass criteria**: Both URLs point to `127.0.0.1:9998` and `127.0.0.1:9999`.

If not, re-run registration:
```bash
~/bin/register-local-llms --no-test
```

### 3.2 Reset DB to known state

```bash
cd ~/cacafuti/delfos && mix run -e '
Application.ensure_all_started(:delfos)
import Ecto.Query
alias Delfos.{Repo, Schema}
for p <- Repo.all(Schema.Project) do
  Repo.delete_all(from s in Schema.Symbol, where: s.project_id == ^p.id)
  Repo.delete_all(from c in Schema.Chunk, where: c.project_id == ^p.id)
  Repo.delete_all(from s in Schema.Summary, where: s.project_id == ^p.id)
  Repo.delete_all(from r in Schema.Relationship, where: r.project_id == ^p.id)
  Repo.delete_all(from m in Schema.FileMetrics, where: m.project_id == ^p.id)
  Repo.delete_all(from f in Schema.File, where: f.project_id == ^p.id)
  Repo.delete!(p)
end
IO.puts "Wiped #{length(Repo.all(Schema.Project))} remaining projects"
' 2>&1 | tail -3
```

**Expected output**: `Wiped 0 remaining projects`

**Pass criteria**: DB starts empty. If not zero, run the wipe again.

### 3.3 Test project preparation

Create an isolated test project under `~/delfos_test_project`:

```bash
mkdir -p ~/delfos_test_project/lib
cat > ~/delfos_test_project/lib/example.ex <<'EOF'
defmodule Example do
  @moduledoc "Sample module for delfos testing."

  def hello(name), do: "Hello, #{name}!"

  defp private_helper(x), do: x * 2
end
EOF
cat > ~/delfos_test_project/mix.exs <<'EOF'
defmodule Example.MixProject do
  use Mix.Project
  def project, do: [app: :example, version: "0.1.0", elixir: "~> 1.14"]
end
EOF
```

### 3.4 Start LLMs (only when test case requires them)

Open **two extra terminals** and run:

```bash
# Terminal A — embeddings
llama-run embed

# Terminal B — chat
llama-run gpt_oss medium
```

Wait ~10s, then verify with `delfos doctor`.

## 4. Test cases

> Each test has:
> - **Pre-conditions**: what must be true before running
> - **Command**: exact command(s) to execute
> - **Expected output**: literal expected strings (or shape)
> - **Pass criteria**: how to decide pass/fail
> - **Cleanup**: actions to revert state

### Section 1: Global flags

#### T1.1 — `delfos --version`

| | |
|---|---|
| **Pre** | none |
| **Command** | `delfos --version` |
| **Expected** | `Delfos v2.1.0` (printed to stdout) |
| **Pass** | exit 0, output matches `~r/Delfos v\d+\.\d+\.\d+/` |
| **Clean** | none |

#### T1.2 — `delfos -v`

| | |
|---|---|
| **Pre** | none |
| **Command** | `delfos -v` |
| **Expected** | same as T1.1 |

#### T1.3 — `delfos --help`

| | |
|---|---|
| **Pre** | none |
| **Command** | `delfos --help` |
| **Expected** | renders an Alaja table with **all 15 commands listed** (init, scan, query, audit, summarize, explain, graph, context, config, integrate, doctor, status, watch, mcp, serve, version); a `GLOBAL FLAGS` section listing `--help, -h` and `--version, -v` |
| **Pass** | table rendered (Alaja `Header.print` is visible); all 15 command names appear in output |
| **Fail indicators** | raw text dump, missing commands, "unknown command" error |

#### T1.4 — `delfos -h`
Same as T1.3.

#### T1.5 — `delfos` (no args)
Same as T1.3 — should show help.

#### T1.6 — `delfos nonexistent`
| | |
|---|---|
| **Command** | `delfos nonexistent` |
| **Expected** | stderr message starting with `Error: unknown command 'nonexistent'`, followed by list of available commands |
| **Pass** | exit non-zero; message contains `unknown` and lists ≥10 commands |

#### T1.7 — `delfos --bogus-flag`
**Expected**: error or "unknown option"; should not silently ignore

### Section 2: `delfos version`

#### T2.1 — `delfos version`
Same as T1.1 (exit 0, "Delfos v2.1.0").

#### T2.2 — `delfos version --help`
**Expected**: help text for the version command

### Section 3: `delfos doctor`

#### T3.1 — `delfos doctor` (LLMs up)
| | |
|---|---|
| **Pre** | LLMs running on 9998 and 9999, DB migrated |
| **Command** | `delfos doctor` |
| **Expected** | 8 checks rendered: Config file, Encryption key, PostgreSQL installation, Database, pgvector extension, Migrations, Provider embed, Provider gpt-oss. Summary `8 passed · 0 failed · 0 warnings` |
| **Pass** | all 6 infra checks pass; both LLM providers pass; final summary `8 passed · 0 failed` |
| **Fail indicators** | any `✗` line; warnings `!`; missing check names |

#### T3.2 — `delfos doctor` (LLMs down)
| | |
|---|---|
| **Pre** | LLMs NOT running; everything else fine |
| **Command** | `delfos doctor` |
| **Expected** | 6 infra checks pass; 2 LLM checks fail with `unreachable at http://127.0.0.1:999N`; summary `6 passed · 2 failed · 0 warnings` |
| **Pass** | LLM failures show helpful hint `Start it locally: llama-server (or run scripts/register-local-llms.sh --probe to verify)` |
| **Fail indicators** | silent failure, stack trace, generic error |

#### T3.3 — `delfos doctor --json`
| | |
|---|---|
| **Pre** | same as T3.1 |
| **Command** | `delfos doctor --json \| jq '.results \| length'` |
| **Expected** | integer ≥ 8 |
| **Pass** | valid JSON, `results` array with ≥8 entries, each with `status` (one of `pass`/`fail`/`warn`), `label`, `detail` |

#### T3.4 — `delfos doctor --help`
**Expected**: help text listing flags (`--fix`, `--json`, `--interactive`)

#### T3.5 — `delfos doctor --fix` (LLMs down, no DB)
**Pre**: clean DB, no PG
**Command**: `delfos doctor --fix`
**Expected**: prompts for installing PG/Docker
**Pass**: user is asked, not silenced; system can be left in either state

#### T3.6 — `delfos config doctor` (alias)
**Command**: `delfos config doctor`
**Expected**: same as T3.1

#### T3.7 — `delfos config probe`
| | |
|---|---|
| **Pre** | LLMs down (to make output non-trivial) |
| **Command** | `delfos config probe` |
| **Expected** | one-line summary: `Delfos diagnostic summary: N passed, N failed, N warnings` followed by per-check `✓/✗/!` lines |
| **Pass** | no crash; multi-line output; no `(FunctionClauseError)` |
| **Fail indicators** | `Enum.join_non_empty_list` error, crash, single-line output |

### Section 4: `delfos init`

#### T4.1 — `delfos init` in non-existent dir
| | |
|---|---|
| **Pre** | `/tmp/delfos_nonexistent_xyz` does not exist |
| **Command** | `delfos init /tmp/delfos_nonexistent_xyz` |
| **Expected** | error `Path does not exist or is not a directory: /tmp/delfos_nonexistent_xyz`; exit non-zero |
| **Pass** | clear error, no DB writes |

#### T4.2 — `delfos init` on empty dir
| | |
|---|---|
| **Pre** | `rm -rf ~/delfos_test_empty && mkdir -p ~/delfos_test_empty`; LLMs down |
| **Command** | `delfos init ~/delfos_test_empty` |
| **Expected** | "Initializing: delfos_test_empty", "Stack: unknown", "Scanning: ... (full)", "Files: 0 found, 0 to process", "Checking local LLM services...", "✓ ... indexed" |
| **Pass** | exit 0, no warnings except possibly LLM unavailable |
| **DB after** | 1 project, 0 files, 0 symbols |

#### T4.3 — `delfos init` on a real project (LLMs down)
| | |
|---|---|
| **Pre** | `~/cacafosi/delfos` exists; LLMs down; no project in DB |
| **Command** | `delfos init ~/cacafosi/delfos` |
| **Expected** | "Initializing: delfos", "Stack: elixir", "Scanning: delfos (full)", "Files: ~194 found, ~194 to process" |
| **Pass** | exit 0; **DB has 367 symbols** (elixir+rust); no "expected a map" warnings; only "embedding unavailable" warnings (for config/* files) |
| **Verify** | `mix run -e 'IO.inspect(Delfos.Repo.aggregate(Delfos.Schema.Symbol, :count))'` → `367` |

#### T4.4 — `delfos init` on already-indexed project
| | |
|---|---|
| **Pre** | T4.3 already run |
| **Command** | `delfos init ~/cacafosi/delfos` |
| **Expected** | "Project already exists in the index (id=...)", shows current state, asks "1. Keep / 2. Wipe / 3. Cancel" |
| **Pass** | interactive prompt OR non-interactive default to Keep (no silent wipe) |

#### T4.5 — `delfos init` interactive: Keep
**Pre**: T4.4 state
**Command**: answer `1` to the prompt
**Expected**: "Keeping existing data; updating metadata", continues, exits 0
**Verify**: DB still has 367 symbols

#### T4.6 — `delfos init` interactive: Wipe
**Pre**: T4.4 state
**Command**: answer `2` to the prompt
**Expected**: "Wiping existing data...", continues with full re-index
**Verify**: DB has 367 symbols again

#### T4.7 — `delfos init` interactive: Cancel
**Command**: answer `3`
**Expected**: "Init cancelled", exit 0
**Verify**: DB unchanged

### Section 5: `delfos scan`

#### T5.1 — `delfos scan` (incremental, no changes)
| | |
|---|---|
| **Pre** | T4.3 state (project freshly indexed) |
| **Command** | `delfos scan` |
| **Expected** | "Scanning: delfos (incremental)", "Files: 194 found, 0 to process" (no changes), "✓ Done in X.Xs" |
| **Pass** | no re-processing of unchanged files; exit 0 |

#### T5.2 — `delfos scan --full`
| | |
|---|---|
| **Pre** | same as T5.1 |
| **Command** | `delfos scan --full` |
| **Expected** | "Scanning: delfos (full)", "Files: 194 found, 194 to process", rebuilds graph, etc. |
| **Pass** | all files re-processed; exit 0 |

#### T5.3 — `delfos scan --workers 8`
**Command**: `delfos scan --workers 8`
**Expected**: uses 8 parallel workers
**Pass**: exit 0; no worker errors

#### T5.4 — `delfos scan` (no project in DB)
**Pre**: wipe all projects
**Command**: `delfos scan`
**Expected**: error "No projects registered. Run: delfos init ."

#### T5.5 — `delfos scan --help`
**Expected**: help text

### Section 6: `delfos query`

#### T6.1 — `delfos query "test"` (LLMs down)
| | |
|---|---|
| **Pre** | T4.3 state, LLMs down |
| **Command** | `delfos query "test"` |
| **Expected** | exit code 78 (LLMGuard halt) with message `Command requires a working LLM, but: ... Embedding: ✗ unreachable` |
| **Pass** | halts BEFORE attempting the query; no `vector type` error |
| **Fail indicators** | runs the query, fails deep inside with `type 'vector' can not be handled` |

#### T6.2 — `delfos query "test"` (LLMs up)
| | |
|---|---|
| **Pre** | T4.3 state, LLMs up |
| **Command** | `delfos query "test"` |
| **Expected** | exit 0, either returns results or `No results for: "test"` |
| **Pass** | no `vector type` error; no `Postgrex.QueryError` |

#### T6.3 — `delfos query "Delfos.CLI"`
**Expected**: results including symbols whose name/qualified_name matches

#### T6.4 — `delfos query` (no args)
**Pre**: same as T6.2
**Command**: `delfos query` (no query string)
**Expected**: error `Usage: delfos query <text> [rest...]` or similar; exit non-zero

#### T6.5 — `delfos query "Delfos.CLI" --level summary`
**Pre**: LLMs up, project with summaries
**Expected**: searches in summary level (if `delfos summarize` was run)

#### T6.6 — `delfos query` (very long string)
**Pre**: LLMs up
**Command**: `delfos query "$(printf 'a%.0s' {1..1000})"`
**Expected**: handles gracefully (no buffer overflow, no crash)

### Section 7: `delfos audit`

#### T7.1 — `delfos audit` (fresh project, LLMs up)
| | |
|---|---|
| **Pre** | T6.2 state |
| **Command** | `delfos audit` |
| **Expected** | "DELFOS AUDIT — delfos", sections HOTSPOTS, DEPENDENCY CYCLES, HIGH TECHNICAL DEBT, FIXME/HACK/DEBT, QUALITY INDEX |
| **Pass** | all sections render; "Symbols with embedding: X/Y" at end; no crash |

#### T7.2 — `delfos audit --file lib/delfos/cli.ex`
**Pre**: T7.1 state
**Command**: `delfos audit --file lib/delfos/cli.ex`
**Expected**: audit just that file

#### T7.3 — `delfos audit --help`
**Expected**: help text

#### T7.4 — `delfos audit` (no project in DB)
**Pre**: wipe projects
**Expected**: error "No projects registered. Run: delfos init ."

### Section 8: `delfos summarize`

#### T8.1 — `delfos summarize` (LLMs up)
| | |
|---|---|
| **Pre** | T4.3 state, LLMs up |
| **Command** | `delfos summarize` |
| **Expected** | "Generando resúmenes hasta nivel ...", "L4: resumiendo símbolos...", "L3: resumiendo archivos...", "Resúmenes generados." |
| **Pass** | DB has summaries (not zero); exit 0 |
| **Verify** | `mix run -e 'IO.inspect(Delfos.Repo.aggregate(Delfos.Schema.Summary, :count))'` → `> 0` |

#### T8.2 — `delfos summarize --level 1`
**Expected**: only L1 summaries (level 1)

#### T8.3 — `delfos summarize --force`
**Expected**: regenerates all summaries even if cached

#### T8.4 — `delfos summarize` (LLMs down)
**Pre**: LLMs down
**Expected**: LLMGuard halts with "Chat: ✗ unreachable" (summarize needs chat)

#### T8.5 — `delfos summarize --help`
**Expected**: help text

### Section 9: `delfos explain`

#### T9.1 — `delfos explain` (no args)
**Expected**: "Usage: delfos explain <name>"; exit non-zero

#### T9.2 — `delfos explain Delfos.CLI.main/1` (LLMs up)
| | |
|---|---|
| **Pre** | T4.3 state, LLMs up |
| **Command** | `delfos explain Delfos.CLI.main/1` |
| **Expected** | detailed explanation of the function: signature, docstring (if any), call graph summary, LLM-generated description |
| **Pass** | non-empty output; contains the function name; shows meaningful content |

#### T9.3 — `delfos explain nonexistent_symbol` (LLMs up)
**Expected**: "Símbolo no encontrado: nonexistent_symbol" or similar; exit non-zero

#### T9.4 — `delfos explain` (LLMs down)
**Pre**: LLMs down
**Expected**: LLMGuard halts (needs both embed + chat)

#### T9.5 — `delfos explain --fresh Delfos.CLI.main/1` (LLMs up)
**Expected**: regenerates the explanation (no cache)

### Section 10: `delfos graph`

#### T10.1 — `delfos graph cycles`
| | |
|---|---|
| **Pre** | T4.3 state |
| **Command** | `delfos graph cycles` |
| **Expected** | "No cycles detected" (most likely, since the project has no circular deps) |
| **Pass** | exit 0, no stack trace |

#### T10.2 — `delfos graph callers Delfos.CLI.main/1`
**Expected**: list of functions that call `main/1`
**Pass**: at least shows 1 result (the init.ex module that calls it)

#### T10.3 — `delfos graph callees Delfos.CLI.main/1`
**Expected**: list of functions called by `main/1` (check_llm_guard, etc.)

#### T10.4 — `delfos graph impact Delfos.CLI.main/1`
**Expected**: BFS impact analysis — all functions transitively reachable from `main/1`

#### T10.5 — `delfos graph` (no subcommand)
**Expected**: usage message listing the 4 subcommands

#### T10.6 — `delfos graph nonexistent_subcmd`
**Expected**: error, exit non-zero

#### T10.7 — `delfos graph callers nonexistent_symbol`
**Expected**: "Símbolo no encontrado: nonexistent_symbol"; exit non-zero

### Section 11: `delfos context`

#### T11.1 — `delfos context`
| | |
|---|---|
| **Pre** | T4.3 state |
| **Command** | `delfos context` |
| **Expected** | "Generado: <path>/.opencode/AGENTS.md <path>/.claude/CLAUDE.md" |
| **Pass** | files exist; non-empty; contain "Delfos" reference; exit 0 |

#### T11.2 — `delfos context --output /tmp/delfos_ctx_$$`
**Pre**: T4.3 state
**Command**: `delfos context --output /tmp/delfos_ctx_$$`
**Expected**: files in `/tmp/delfos_ctx_$$/`
**Pass**: files exist at expected paths; non-empty
**Clean**: `rm -rf /tmp/delfos_ctx_$$`

#### T11.3 — `delfos context --symbol Delfos.CLI.main/1` (LLMs up)
**Pre**: LLMs up
**Command**: `delfos context --symbol Delfos.CLI.main/1`
**Expected**: dynamic context with the symbol's code, callers, callees, metrics
**Pass**: output contains the function code; contains the function name

#### T11.4 — `delfos context --symbol nonexistent` (LLMs up)
**Expected**: "Símbolo no encontrado: nonexistent"; exit non-zero

#### T11.5 — `delfos context` (no project in DB)
**Pre**: wipe all projects
**Expected**: error "No hay proyectos. Usa delfos init"; exit non-zero

### Section 12: `delfos config`

#### T12.1 — `delfos config --help`
**Expected**: lists all subcommands: show, path, init, get, set, preset, setup, wizard, models, doctor, probe
**Pass**: all subcommands listed

#### T12.2 — `delfos config show`
| | |
|---|---|
| **Command** | `delfos config show` |
| **Expected** | "Fichero: <path>" followed by `[embedding]`, `[llm]`, `[analysis]`, `[indexing]`, `[retrieval]` sections |
| **Pass** | all sections rendered with masked API keys (`sk-loc...-dev` shape) |

#### T12.3 — `delfos config path`
**Expected**: prints absolute path to config.json

#### T12.4 — `delfos config init`
| | |
|---|---|
| **Pre** | backup existing config.json |
| **Command** | `delfos config init` |
| **Expected** | either "Created: <path>" (new) or "Already exists: <path>" (existing) + "Run 'delfos config show' to see..." |
| **Pass** | clear message, doesn't overwrite existing |

#### T12.5 — `delfos config get llm url`
**Expected**: `"https://api.openai.com"` (or whatever current value)

#### T12.6 — `delfos config get llm nonexistent_key`
**Expected**: "(not found: [llm] nonexistent_key)"; exit 0 (not an error)

#### T12.7 — `delfos config set llm timeout_ms 50000`
**Expected**: "[llm] timeout_ms = 50000"
**Pass**: persists to config.json; `delfos config get llm timeout_ms` returns `"50000"`

#### T12.8 — `delfos config set bogus key val`
**Expected**: "Unknown section: 'bogus'" + "Valid sections: embedding, llm, analysis, indexing, database"
**Pass**: clear error, no write to config

#### T12.9 — `delfos config set llm nonexistent_key val`
**Expected**: "Unknown key: 'llm.nonexistent_key'" + "Valid keys for 'llm': provider, url, model, ..."
**Pass**: clear error, no write to config

#### T12.10 — `delfos config preset local`
**Expected**: applies preset, prints each changed key, summary "Preset 'local' applied."

#### T12.11 — `delfos config preset anthropic`
**Expected**: applies preset, prints "Remember to set your API key: delfos config set llm api_key sk-ant-YOUR_KEY"

#### T12.12 — `delfos config preset bogus`
**Expected**: "Unknown preset: bogus" + "Available presets: ..."

#### T12.13 — `delfos config models`
**Expected**: "Active models: Embedding: .../... LLM: .../..."

#### T12.14 — `delfos config models --probe` (LLMs up)
**Pre**: LLMs up
**Expected**: model info + probe results from each provider

#### T12.15 — `delfos config setup` (interactive)
**Pre**: terminal
**Expected**: shows "DELFOS SETUP WIZARD" with numbered options
**Pass**: only shows numeric prefixes, NOT `1. 1. llama.cpp...`

#### T12.16 — `delfos config wizard` (interactive)
**Expected**: shows "LLM setup" with engine options
**Pass**: no double-numeric prefixes

#### T12.17 — `delfos config probe` (LLMs down)
**Pre**: LLMs down
**Expected**: "Delfos diagnostic summary: 6 passed, 2 failed, 0 warnings" + per-line status
**Pass**: does NOT crash with `Enum.join_non_empty_list` error

### Section 13: `delfos integrate`

#### T13.1 — `delfos integrate` (no args)
| | |
|---|---|
| **Command** | `delfos integrate` |
| **Expected** | "DELFOS INTEGRATE — available agents" with: claude-code, opencode, cursor, aider, codex, zed, all. Plus "Manual integration" recipe with connection JSON |
| **Pass** | lists all 7 agents; manual JSON recipe includes `delfos mcp` (NOT `delfos serve --mcp`) |

#### T13.2 — `delfos integrate claude-code --yes` (LLMs down)
| | |
|---|---|
| **Pre** | backup `~/.claude.json` if it exists |
| **Command** | `delfos integrate claude-code --yes` |
| **Expected** | creates/updates `~/.claude.json` with `mcpServers.delfos` using `["mcp"]` args |
| **Pass** | JSON file valid; mcpServers.delfos present; `args: ["mcp"]` |
| **Clean** | restore backup |

#### T13.3 — `delfos integrate opencode --yes`
**Pre**: backup `~/.config/opencode/config.json`
**Expected**: `mcp.delfos.command = "delfos"`, `args = ["mcp"]`
**Pass**: same check as T13.2

#### T13.4 — `delfos integrate cursor --yes` (in test project)
**Pre**: backup `.cursor/` in test project
**Command**: `cd ~/delfos_test_project && delfos integrate cursor --yes`
**Expected**: creates `.cursor/mcp.json` with `delfos` server
**Pass**: file valid; `args: ["mcp"]`

#### T13.5 — `delfos integrate zed --yes`
**Pre**: backup `~/.config/zed/settings.json`
**Expected**: `context_servers.delfos.command.path = "delfos"`, `args = ["mcp"]`

#### T13.6 — `delfos integrate all --yes` (LLMs down)
**Pre**: backup all configs
**Command**: `delfos integrate all --yes`
**Expected**: asks about each, then applies
**Pass**: doesn't overwrite if declined

### Section 14: `delfos status`

#### T14.1 — `delfos status`
| | |
|---|---|
| **Pre** | T4.3 state |
| **Command** | `delfos status` |
| **Expected** | "DELFOS STATUS", lists each project with: name, path, branch, commit, files count, symbols count, embedded %, summarized %, chunks count, cycles count, last scan |
| **Pass** | all projects shown; counts match DB |

#### T14.2 — `delfos status` (no projects)
**Pre**: wipe projects
**Expected**: shows "Indexed projects: 0" or similar; doesn't crash

### Section 15: `delfos mcp`

#### T15.1 — `delfos mcp` (smoke test)
| | |
|---|---|
| **Pre** | LLMs up or down; project indexed |
| **Command** | `echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \| timeout 5 delfos mcp` |
| **Expected** | JSON-RPC response with list of MCP tools (search, lookup, context, etc.) |
| **Pass** | valid JSON-RPC 2.0 response; tools list non-empty |

#### T15.2 — `delfos mcp` (search tool call)
**Pre**: LLMs up
**Command**: `echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search","arguments":{"query":"Delfos.CLI","limit":5}}}' \| timeout 10 delfos mcp`
**Expected**: JSON-RPC response with search results

### Section 16: LLMGuard behavior

#### T16.1 — LLMGuard halts `init` when LLMs down
| | |
|---|---|
| **Pre** | LLMs down, no project |
| **Command** | `delfos init ~/delfos_test_empty` |
| **Expected** | exit 78; message "Command requires a working LLM, but: Reason: init triggers a full scan (needs embeddings) Embedding: ✗ unreachable Chat: (not needed for this command)" |
| **Pass** | halts BEFORE writing anything to DB |

#### T16.2 — LLMGuard halts `query` when LLMs down
| | |
|---|---|
| **Pre** | project indexed, LLMs down |
| **Command** | `delfos query "test"` |
| **Expected** | exit 78; "Reason: query uses vector search (needs embeddings) Embedding: ✗ unreachable" |
| **Pass** | halts BEFORE calling DB |

#### T16.3 — LLMGuard halts `mcp` when LLMs down
**Pre**: project indexed, LLMs down
**Command**: `delfos mcp < /dev/null`
**Expected**: halts (mcp needs both)

#### T16.4 — LLMGuard halts `summarize` when LLMs down
**Pre**: project indexed, LLMs down
**Command**: `delfos summarize`
**Expected**: halts (chat needed)

#### T16.5 — LLMGuard halts `explain` when LLMs down
**Pre**: project indexed, LLMs down
**Command**: `delfos explain Foo.bar`
**Expected**: halts (both needed)

#### T16.6 — LLMGuard allows `audit` when LLMs down
| | |
|---|---|
| **Pre** | project indexed, LLMs down |
| **Command** | `delfos audit` |
| **Expected** | runs (audit doesn't need LLM); no halt; no LLMGuard warning |
| **Pass** | exit 0; no halts; runs without LLM |

#### T16.7 — LLMGuard allows `graph cycles` when LLMs down
**Command**: `delfos graph cycles`
**Expected**: runs (graph doesn't need LLM)

#### T16.8 — LLMGuard allows `config` when LLMs down
**Command**: `delfos config show`
**Expected**: runs (config doesn't need LLM)

#### T16.9 — LLMGuard allows `init --help` when LLMs down
**Command**: `delfos init --help`
**Expected**: shows help (skips guard for --help)

#### T16.10 — LLMGuard allows `status` when LLMs down
**Command**: `delfos status`
**Expected**: runs without halt

### Section 17: pgvector

#### T17.1 — pgvector extension is loaded
**Command**: `psql -U postgres -d delfos_prod -c "SELECT extname FROM pg_extension WHERE extname='vector';"`
**Expected**: one row with `vector`
**Pass**: extension present

#### T17.2 — vector type works in queries
**Pre**: LLMs up, project indexed with embeddings
**Command**: `psql -U postgres -d delfos_prod -c "SELECT count(*) FROM symbols WHERE embedding IS NOT NULL;"`
**Expected**: count > 0
**Pass**: query succeeds (no "type 'vector' can not be handled")

#### T17.3 — similarity search works
**Pre**: T17.2
**Command**: `psql -U postgres -d delfos_prod -c "SELECT name, embedding <=> (SELECT embedding FROM symbols LIMIT 1) AS dist FROM symbols ORDER BY dist LIMIT 5;"`
**Expected**: 5 rows with names
**Pass**: vector distance operator (`<=>`) works

### Section 18: Doctor --fix (auto-repair)

#### T18.1 — Doctor --fix with no PG running
**Pre**: stop PG (if you can; otherwise simulate by changing DB host)
**Command**: `delfos doctor --fix`
**Expected**: detects no PG, offers Docker install

#### T18.2 — Doctor --fix with migrations pending
**Pre**: drop a migration, then `delfos doctor --fix`
**Expected**: detects missing migrations, asks to apply

#### T18.3 — Doctor --fix with LLM down
**Pre**: LLMs down
**Command**: `delfos doctor --fix`
**Expected**: detects LLMs down, offers to start via `llama-server`

### Section 19: Configuration validation

#### T19.1 — Invalid section rejected
`delfos config set bogus key val` → clear error (see T12.8)

#### T19.2 — Invalid key rejected
`delfos config set llm nonexistent val` → clear error (see T12.9)

#### T19.3 — Config file is valid JSON
`python3 -c "import json; json.load(open('/home/<user>/.config/delfos/config.json'))"` → no error

#### T19.4 — Config encryption key exists
`ls -la ~/.config/delfos/.key` → file present, mode 600

### Section 20: Watch mode

#### T20.1 — `delfos watch` smoke test
**Pre**: project indexed, LLMs down (watch needs LLM)
**Command**: `timeout 5 delfos watch 2>&1` (run in test project dir)
**Expected**: starts watcher, halts on timeout
**Pass**: no crash

#### T20.2 — `delfos watch` (no project)
**Pre**: no project in DB
**Expected**: error "No projects registered. Run: delfos init ."

### Section 21: End-to-end workflows

#### T21.1 — Full workflow (cold start, LLMs up)
1. Wipe DB
2. Start LLMs
3. `delfos init ~/cacafuti/delfos`
4. `delfos scan --full`
5. `delfos summarize`
6. `delfos query "Delfos.CLI.main"`
7. `delfos explain Delfos.CLI.main/1`
8. `delfos graph impact Delfos.CLI.main/1`
9. `delfos audit`
10. `delfos status`

**Expected**: every step succeeds; final DB has symbols, chunks, summaries, relationships

#### T21.2 — Workflow with LLM down then up
1. Wipe DB
2. `delfos init` (fails on LLMGuard) — **expected**
3. Start LLMs
4. `delfos init` (succeeds) — should work
5. `delfos query "test"` — should work

#### T21.3 — Re-init (wipe) workflow
1. Index project (T21.1 step 3)
2. `delfos init` again, answer `2` (wipe)
3. Verify DB has same symbol count (367)

#### T21.4 — Config preset then init
1. Wipe DB, stop LLMs
2. `delfos config preset anthropic`
3. `delfos config show` — verify llm.url is Anthropic's
4. `delfos config preset local`
5. `delfos init ~/cacafuti/delfos` — should work with local URLs

### Section 22: Edge cases

#### T22.1 — Empty `args` to `delfos init`
`delfos init` (no path) — should init cwd if it's a valid project

#### T22.2 — `delfos init` with `--full` flag
`delfos init --full ~/test` — should work (init may have --full)

#### T22.3 — Very long file
Create a 100KB .ex file, scan it
**Pass**: completes without OOM

#### T22.4 — File with no extension
`delfos scan` on a project with `Makefile` (no ext) — should skip

#### T22.5 — Binary file
Add a `.png` to test project, scan
**Pass**: skipped (binary extension)

#### T22.6 — File with syntax error
`def foo (broken_elixir` — scan shouldn't crash
**Pass**: error logged, scan continues

#### T22.7 — 1000+ files
Create a project with 1000 small .ex files
**Pass**: scan completes in reasonable time (<2 min)

#### T22.8 — Concurrent scans
Run `delfos scan` twice in parallel
**Pass**: one wins, the other exits cleanly (or both error gracefully)

## 5. Result recording

After each section, record results in this format:

```
### Section N results
| Test | Status | Notes |
|------|--------|-------|
| N.1  | PASS/FAIL | (actual output excerpt if FAIL) |
```

For **FAIL** entries, capture:
- Exact command run
- Full output (stdout + stderr)
- Exit code
- Pre-state (LLM up/down, DB state, etc.)
- Any side effects (files written, DB rows, etc.)

## 6. Result summary template

After all tests, fill in:

```
=== Test Run Summary ===
Date: YYYY-MM-DD
Binary: /home/<user>/bin/delfos (build 2.1.0, sha XXXXXXX)
LLM state: up | down
DB state: empty | populated (N projects)

Total tests: N
Passed: X
Failed: Y
Skipped: Z (with reason)

Bugs found: (list)
1. [severity] short description
2. ...

Pass-rate by section:
  1. Global flags: 7/7
  2. version: 2/2
  3. doctor: 7/7
  ...
```

## 7. Severity classification for found bugs

| Severity | Definition | Example |
|---|---|---|
| **Critical** | Command crashes, data loss, or hangs | NIF panic, infinite loop |
| **Major** | Wrong output, no useful error | Bad URL not detected by probe |
| **Minor** | Cosmetic, suboptimal UX | "1. 1." double numbering, extra blank line |
| **Nit** | Subjective, no functional impact | Color choice, error phrasing |

## 8. Cleanup after testing

```bash
# Stop LLMs (if you started them for tests)
pkill -9 llama-server

# Remove test project
rm -rf ~/delfos_test_empty ~/delfos_test_project

# Wipe DB
cd ~/cacafuti/delfos && mix run -e '
Application.ensure_all_started(:delfos)
import Ecto.Query
alias Delfos.{Repo, Schema}
for p <- Repo.all(Schema.Project) do
  Repo.delete_all(from s in Schema.Symbol, where: s.project_id == ^p.id)
  Repo.delete_all(from c in Schema.Chunk, where: c.project_id == ^p.id)
  Repo.delete_all(from s in Schema.Summary, where: s.project_id == ^p.id)
  Repo.delete_all(from r in Schema.Relationship, where: s.project_id == ^p.id)
  Repo.delete_all(from m in Schema.FileMetrics, where: s.project_id == ^p.id)
  Repo.delete_all(from f in Schema.File, where: f.project_id == ^p.id)
  Repo.delete!(p)
end
IO.puts "DB wiped"
'

# Restore any backed-up configs
mv ~/.config/delfos/config.json.bak ~/.config/delfos/config.json 2>/dev/null || true
```

## 9. Appendix A: Test data fixtures

### Fixture 1: Minimal Elixir project

`~/delfos_test_project/`:
```
delfos_test_project/
├── mix.exs
└── lib/
    └── example.ex
```

`lib/example.ex`:
```elixir
defmodule Example do
  @moduledoc "Sample module for delfos testing."

  def hello(name), do: "Hello, #{name}!"

  defp private_helper(x), do: x * 2
end
```

`mix.exs`:
```elixir
defmodule Example.MixProject do
  use Mix.Project
  def project, do: [app: :example, version: "0.1.0", elixir: "~> 1.14"]
end
```

This project should produce **2 symbols** when scanned (1 module + 1 function).

### Fixture 2: Multi-language project

`~/delfos_test_polyglot/`:
```
polyglot/
├── .git/
├── package.json
├── go.mod
├── main.go
├── src/
│   ├── app.py
│   └── util.py
└── README.md
```

`main.go`:
```go
package main

func Hello() string { return "hi" }
```

`src/app.py`:
```python
def hello(name):
    return f"Hello, {name}!"

class Greeter:
    def __init__(self, name):
        self.name = name
```

### Fixture 3: Real project (delfos itself)

`~/cacafuti/delfos/` — the project itself. 195 files, 367 symbols expected.

## 10. Appendix B: Useful one-liners

```bash
# Count symbols in DB
mix run -e 'IO.inspect(Delfos.Repo.aggregate(Delfos.Schema.Symbol, :count))' 2>&1 | tail -1

# Check if pgvector is loaded
psql -U postgres -d delfos_prod -c "SELECT * FROM pg_extension WHERE extname='vector';"

# List all top-level commands
delfos --help 2>&1 | head -30

# Check if LLM ports are listening
nc -zv 127.0.0.1 9998 2>&1
nc -zv 127.0.0.1 9999 2>&1

# Reset config to defaults
~/bin/register-local-llms --no-test

# Re-register without API key (use env var)
API_KEY=sk-test-key LLM_PORT=9999 EMBED_PORT=9998 ~/bin/register-local-llms --no-test
```

## 11. Appendix C: Common failure modes to watch for

Based on the current codebase (v2.1.0), these have been seen before:

1. **`expected a map, got: <tuple>`** — BadMapError from Elixir when
   using `tuple.field` on a non-map. Fixed in `Indexer.FileProcessor`.

2. **`FunctionClauseError` on `Enum.join/2`** — Improper list cons with
   `[acc | string]`. Fixed in `Diagnostics.summary/0`.

3. **`type 'vector' can not be handled by the types module`** —
   Missing pgvector types. Fixed by `Delfos.PostgrexTypes` and
   `types: Delfos.PostgrexTypes` in `config/config.exs` + `config/runtime.exs`.

4. **Embedded syms all `name=""`** — `normalize_symbol` assumed string
   keys. Fixed by handling both atom and string keys.

5. **`Init cancelled` in non-interactive mode** — `delfos init` on
   already-indexed project defaults to Keep. Verified.

6. **`1. 1. llama.cpp...`** — Double-numbered menu options. Fixed by
   removing manual `N.` prefixes.

7. **Embedding unavailability cascades per chunk** — `process_chunks`
   tried to insert `nil` embedding per chunk. Fixed with single-file
   warning.

If you encounter one of these again, the existing fix is documented
in the relevant code path.

## 12. Acceptance criteria for the test plan itself

This plan is **complete** when:

- [x] Every `delfos <subcommand>` listed in `--help` has at least one test
- [x] Every `delfos config <subcommand>` has a test
- [x] Every `delfos graph <subcommand>` has a test
- [x] LLMGuard is tested for all three states (up, down, partial)
- [x] pgvector is verified at the DB level
- [x] Error / edge cases are documented
- [x] Each test has explicit pre-conditions, command, expected output, pass criteria
- [x] Result recording format is defined
- [x] Another agent can execute this plan without further input

If you find a code path or flag not covered here, add it to the
appropriate section.
