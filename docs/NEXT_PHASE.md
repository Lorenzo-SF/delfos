# Delfos — NEXT_PHASE

> **Single source of truth for the next implementation phase.**
> A fresh agent in a new `opencode` session should be able to read this
> document end-to-end and execute the next phase without needing to
> re-explore the codebase.
>
> Generated on 2026-07-07, immediately after tagging `delfos 2.0.0`.

---

## 0. TL;DR for a fresh agent

- **Repo**: `/home/merendandum/cacafuti/delfos` (the user's working copy is
  here). On GitHub it's `Lorenzo-SF/delfos`.
- **Current version**: `2.0.0` (tagged on HEAD of `main`, commit `2faf413`).
- **Stack**: Elixir 1.19.5, OTP 28, Phoenix-flavored Ecto + PostgreSQL 15–17
  with `pgvector`, Rust NIF (`tree_sitter` 0.25), Batimanta for release
  bundling, `Alaja.CLI.Definition` DSL for the CLI.
- **Ecosystem deps**: all pinned to `branch: "main"` on GitHub. Never pin
  to tags. See §3.
- **Test status**: `mix test` → 179 tests, 0 failures, 2 skipped (explicit
  `@tag :skip`), 12 excluded (the `@tag :integration` set — they need a
  live Postgres). See §4.
- **What works**: CLI (17 commands), MCP server (8 tools), hybrid search,
  watcher, build pipeline. See §2.
- **What is in flight / not merged**: handler-bridge anti-pattern removal,
  a `RepoStarter` pre-flight, Apero-dep removal — all sitting on
  `origin/fix/repo-startup-and-bridge` (3 commits ahead of `main`). See
  §6.1.
- **What is stubbed / broken**: 3 pre-existing dialyzer warnings (see
  §5.1), powershell/groovy/perl/vb tree-sitter grammars still on the
  regex `GenericParser` (see §2.4), no `--version` global flag (see
  §2.5), some CLI command tests only have `--help` smoke coverage (see
  §4.3).
- **Phase plan**: see §7. The work is ordered to land in 6 small PRs that
  don't touch the public MCP or DB schema.
- **Acceptance for the next release (2.1.0 or 3.0.0)**: see §9.

---

## 1. Project state at HEAD

| Item | Value |
|---|---|
| Working tree | clean on `main` |
| HEAD | `2faf413` — `chore(delfos): redo CHANGELOG as 2.0.0 + bump version 0.4.19 -> 2.0.0 + drop v prefix from source_ref (#4)` |
| Tags | `1.0.0`, `2.0.0` (no `v` prefix; matches botica/candil convention) |
| Branch | `main` |
| Other branches on remote | `cleanup/delfos-quality`, `feat/candil-llm-client-v2`, `fix/repo-startup-and-bridge`, `m3-delfos-audit` |
| `mix.exs` `@version` | `2.0.0` |
| `mix.exs` `source_ref` | `"1.0.0"` (literal, no `v` prefix; matches botica PR #21 / candil PR #8 convention) |
| `mix.exs` `version:` | `@version` (interpolation) |
| `CHANGELOG.md` | collapsed to `[2.0.0]` + `[1.0.0]` headers; all `[0.x]` planning milestones removed |
| `config/config.exs` | `mix format --check-formatted` clean (extra blank line fixed during the 2.0.0 PR) |

### 1.1 Recent opencode session context

The user referenced two prior opencode sessions in the request that
produced this document:

- `ses_0d0b18da6ffe590mImuo1pgmfO` — an earlier session that did Phase 0
  (critical bugs) → Phase 1 (Diagnostics + Probe) → Phase 2 (doctor
  refactor) → Phase 3 (tests for Diagnostics + Probe). The relevant
  commits are still on `main` as `05f7544`, `f99524b`, `0507a48`, `7513fa9`,
  `842b773`.
- `ses_0c965852fffe7L3ofp3ClkbFBR` — the most recent session, which did
  the batamanta-pin cleanup (`f22dfdf`, `6c7a8ef`, `3d3116f`, `cfd7aa6`,
  `a8963bb`, `83ebc3d`), added powershell/groovy/perl tree-sitter
  attempts (`12fa68c`, `d50ed4b`), added MCP server hardening
  (`153112e`, `ad576da`), routed explain/audit/query through
  `Delfos.Syntax.Utils` (`e7e61a8`, `3ceb58a`), and added the test suites
  for every CLI command (`d32429a`, `97c5cd2`, `2db84c7`, `e6e395c`,
  `8a61571`, `e69fc47`, `0637015`, `cf303f1`, `c7ef6f4`, `92ca102`,
  `e7d32e6`, `68a3df0`). It ended with the pre-revision commits
  `83b14f3` ("guardado pre fi x") and `df11036` ("guardado prerevision 2").

**These sessions are not directly accessible from this one** — the
session IDs are for context only. If the user re-opens them, the
content should match the commit history above.

### 1.2 Critical conventions (read before touching anything)

From `docs/HANDOFF.md` and `SPEC.md`, with my own additions:

1. **Spanish in chat, English in code/files/CHANGELOG/commit messages.**
   No exceptions.
2. **Git dates in the 20:00–02:00 Europe/Berlin window** for weekday
   commits (or anytime on weekends). See the `git_commit` shell function
   at `/home/merendandum/.zshrc:183` — it sets `GIT_AUTHOR_DATE` and
   `GIT_COMMITTER_DATE` to `now - 12h`. Use it via
   `source /home/merendandum/.zshrc && git_commit "<message>"`.
3. **Ecosystem deps pinned to `branch: "main"`**, never tags, never
   `path:` in committed `mix.exs`. The local `path: "../alaja"` is OK
   inside the umbrella workspace but the committed `mix.exs` must use
   `github: "Lorenzo-SF/<lib>", branch: "main"`. See `mix.exs:50–80`.
4. **Commit messages**: conventional commits in English
   (`fix(delfos): …`, `feat(delfos): …`, `chore(delfos): …`,
   `docs(delfos): …`, `refactor(delfos): …`, `test(delfos): …`).
5. **`batamanta: [format: :release, …]`** is mandatory in `mix.exs`.
   `format: :escript` silently drops the Rust NIF. See `mix.exs:180–193`
   and the historical bug in CHANGELOG `[0.4.17]`.
6. **`include_erts: false` + `Alaja.CLI.Definition.dispatch_main/1`
   auto-starts the OTP app**. Without both, every command fails with
   `could not lookup Ecto repo Delfos.Repo because it was not started`.
   See `mix.exs:201–216` and `alaja/lib/alaja/cli/definition.ex:241–256`.
7. **No `--warnings-as-errors`** in delfos CI. It triggers false
   positives from `mix.exs` aliases.
8. **No `mix cover` / Coveralls in CI**. It would require a token.

---

## 2. What works (current state of delfos)

### 2.1 CLI

Entry point: `Delfos.CLI` (`lib/delfos/cli.ex`), defined via
`use Alaja.CLI.Definition, otp_app: :delfos`. 17 commands declared:

| Command | Handler | File | Tests |
|---|---|---|---|
| `init` | `init_handler/1` | `cli/commands/init.ex` | `cli/commands/init_test.exs` (smoke + `@tag :integration`) |
| `scan` | `scan_handler/1` | `cli/commands/scan.ex` | `cli/commands/scan_test.exs` |
| `query` | `query_handler/1` | `cli/commands/query.ex` | `cli/commands/query_test.exs` |
| `audit` | `audit_handler/1` | `cli/commands/audit.ex` | `cli/commands/audit_test.exs` |
| `summarize` | `summarize_handler/1` | `cli/commands/summarize.ex` | `cli/commands/summarize_test.exs` |
| `explain` | `explain_handler/1` | `cli/commands/explain.ex` | `cli/commands/explain_test.exs` |
| `graph` | `graph_handler/1` | `cli/commands/graph.ex` | `cli/commands/graph_test.exs` |
| `context` | `context_handler/1` | `cli/commands/context.ex` | `cli/commands/context_test.exs` |
| `config` | `config_handler/1` | `cli/commands/config.ex` | `cli/commands/config_test.exs` |
| `integrate` | `integrate_handler/1` | `cli/commands/integrate.ex` | `cli/commands/integrate_test.exs`, `integrate_formats_test.exs` |
| `doctor` | `doctor_handler/1` | `cli/commands/doctor.ex` | `cli/commands/doctor_test.exs` |
| `models` | `models_handler/1` | `cli/commands/models.ex` | `cli/commands/models_test.exs` |
| `status` | `status_handler/1` | `cli/commands/status.ex` | `cli/commands/status_test.exs` |
| `watch` | `watch_handler/1` | (inline in `cli.ex`) | — |
| `serve` | `serve_handler/1` | (inline in `cli.ex`) — calls `Delfos.MCP.Server.start/0` on `--mcp` | — |
| `version` | `version_handler/1` | (inline in `cli.ex`) | covered in `cli_test.exs` |
| `setup` | `setup_handler/1` | `cli/commands/setup.ex` + `cli/commands/setup/{db,llm}.ex` | `cli/commands/setup_test.exs`, `setup_db_test.exs`, `setup_llm_test.exs` |

The DSL integration is correct: `__commands__/0` returns all 17 commands
in declaration order, each has a description and a `{Mod, Fun}` run
handler. `main/1` boots `:alaja` + `:delfos` before dispatching.

### 2.2 MCP server

`lib/delfos/mcp/server.ex` exposes 8 JSON-RPC 2.0 tools over stdio
(protocol version 2024-11-05). Tool names: `search`, `symbol`,
`context`, `callers`, `callees`, `impact`, `audit`, `files`.

- Hardened against slow tools (timeout + try/rescue around dispatch).
- Safe `Jason.encode` (no `!`).
- Async stdin reader (no `after: 0` spin loop).
- Build-time dispatch via `Alaja.CLI.Definition.exec/1` is **not used**
  here — the server has its own JSON-RPC loop, separate from the CLI.

### 2.3 Database + search

- 10 Ecto migrations in `priv/repo/migrations/` (8 core + 1 vector-dim
  fix + 1 HNSW indexes).
- Hybrid search: vector (pgvector) + BM25 + graph via Reciprocal Rank
  Fusion (`lib/delfos/retrieval/hybrid_search.ex`).
- `Delfos.Health` does periodic pings of the embedding and LLM
  endpoints, reports latency + dim mismatch.
- `config/runtime.exs` validates env vars in production.

### 2.4 Tree-sitter NIF

`native/tree_sitter_nif/Cargo.toml` declares grammars in 3 tiers:

- **Tier 1 (mature)**: elixir, typescript, javascript, python, rust, go,
  java, c-sharp, c, cpp, php, ruby, swift, dart, objc, kotlin-ng.
- **Tier 2 (stable)**: scala, lua, bash, json, yaml, r, asm, fsharp,
  powershell (pinned `=0.25.10`), groovy (pinned `=0.1.2`).
- **Tier 3 (extended)**: haskell, erlang, ocaml, clojure, zig, gleam,
  julia, hcl.

`lib/delfos/parsers/treesitter/tree_sitter.ex#language_for/1` routes
each `@supported_languages` atom to the NIF or to the regex
`GenericParser`.

**Still on the regex fallback**: `perl` (intentionally omitted — see
the explanatory comment in `Cargo.toml:66–79`), `vb` (no
`tree-sitter-vbnet` published on crates.io). Powershell and Groovy
grammars are declared but their NIF entries are not yet exposed — see
§6.4.

### 2.5 CLI DSL quirks (already documented; do not regress)

- `--help` and `-h` work "by accident": they hit
  `Alaja.CLI.ErrorHandler.unknown_command/2` which prints the available
  commands list along with the error. The `cli_test.exs` tests confirm
  the output contains the command names. Not pretty but functional.
- `--version` and `-v` are **not** global. They hit the same unknown
  command path. Use `delfos version` instead. (Documented in §7.3 as
  something to fix.)
- The `serve` command's fallback handler does
  `Delfos.CLI.Commands.Config.run(["help"])` when `--mcp` is missing.
  This looks like leftover from an earlier draft — `delfos serve`
  without `--mcp` should probably show a help block specific to
  `serve`, not delegate to `config help`. See §6.5.

### 2.6 Build pipeline

- `mix gen` → `["batamanta", "deploy"]` — builds the release binary and
  copies it to `~/bin/delfos`. Alias in `mix.exs:107`.
- `mix deploy` — copies `./delfos` → `~/bin/delfos` (after `batamanta`
  produced the binary). Alias in `mix.exs:126–155`.
- `mix tools_version` — writes `~/bin/.tool-versions` for
  asdf/mise. Alias in `mix.exs:156–161`.
- `mix quality` → `format + compile --warnings-as-errors + test +
  credo --strict + run bench + coveralls + dialyzer`. Note: this is
  the local "all gates" alias; CI runs only the subset that fits the
  runner (no Rust toolchain in `Lint` job).

---

## 3. Dependency status

### 3.1 Ecosystem deps (from `mix.exs:50–81`)

| Dep | Source | Why pinned like this |
|---|---|---|
| `alaja` | `~> 2.0.0` | Alaja was just bumped to 2.0.0 in the same session. The `~> 2.0.0` constraint matches the released tag. |
| `candil` | `github: "Lorenzo-SF/candil", branch: "main"` | Pinned to main per project convention. Last released tag is 2.0.0 (not declared in `mix.exs`; expected behaviour). |
| `arrea` | `github: "Lorenzo-SF/arrea", branch: "main"` | Same. |
| `apero` | `github: "Lorenzo-SF/apero", branch: "main"` | Same. |
| `botica` | `github: "Lorenzo-SF/botica", branch: "main"` | Same. |
| `batamanta` | `path: "../batamanta"` if sibling exists, else `github: "...", branch: "fix/erlexec-config-flag", override: true` | Local development uses the sibling checkout for fast iteration; CI falls back to the GitHub branch. See `batamanta_dep/0` in `mix.exs:167–178`. |

**Important**: never change `branch: "main"` to a tag. The
`Lorenzo-SF/<lib>` ecosystem has had breaking changes between tags
historically (pote v0.2.0, candil v0.2.0, alaja v0.3.8 — see
CHANGELOG `[0.4.13]`).

### 3.2 Third-party deps

| Dep | Version | Notes |
|---|---|---|
| `ecto_sql` | `~> 3.11` | OK |
| `postgrex` | `~> 0.18` | OK |
| `pgvector` | `~> 0.3` | HNSW indexes in migration `20260628000001_add_hnsw_indexes.exs` |
| `req` | `~> 0.5` | **Vulnerable** — see `EEF-CVE-2026-49756` (LOW) and `EEF-CVE-2026-49755` (HIGH). See `mix deps.get` output. **Action item in §7.5.** |
| `file_system` | `~> 1.0` | OK |
| `jason` | `~> 1.4` | OK |
| `toml` | `~> 0.7` | OK |
| `tree_sitter` | `~> 0.0.3`, `runtime: false` | OK (NIF host) |
| `rustler` | `~> 0.34.0`, `runtime: false` | OK |
| `mix_test_watch` | `~> 1.1`, `only: :dev` | OK |
| `ex_doc` | `~> 0.31`, `only: :dev` | OK |
| `dialyxir` | `~> 1.4`, `only: [:dev, :test]` | OK |
| `credo` | `~> 1.7`, `only: [:dev, :test]` | OK |
| `mox` | `~> 1.1`, `only: :test` | OK |

### 3.3 Removed runtime deps (from CHANGELOG)

- `yaml_elixir ~> 2.11` — was removed when `merge_aider_read/1` switched
  to a regex-based approach.

---

## 4. Test status

### 4.1 Counts at HEAD `2faf413`

```
mix test                  → 179 tests, 0 failures, 2 skipped, 12 excluded
mix test --include integration → 179 tests, 5 failures, 2 skipped
  (the 5 failures are inside the 12 integration-tagged tests that
  need a live Postgres — they fail because there is no Postgres
  available in the current sandbox)
```

The 12 `@tag :integration` tests (distributed across
`test/delfos/cli/commands/{audit,context,doctor,explain,graph,init,query,scan,status,summarize}_test.exs`)
are DB-touching smoke tests. CI runs them against a `pgvector/pgvector:pg16`
service container (`.github/workflows/ci.yml:54–118`).

The 2 `@tag :skip` tests are in `test/delfos/integration_test.exs`:

- `parse/2 for unsupported extensions returns error` (line 101) —
  skipped because the dispatcher's `:unsupported_extension` return
  isn't part of the current behaviour (the dispatcher routes unknown
  extensions to the regex `GenericParser`, which always returns `{:ok,
  ...}`). See §7.6.
- `uses Arrea.run_sync (public facade), not Arrea.Parallel (internal)`
  (line 188) — skipped because it depends on `Code.fetch_docs/1`
  runtime metadata that is unreliable in test mode. The
  `@moduledoc false` check is enforced manually during code review.

### 4.2 Test files inventory

```
test/
├── alaja/                       # 1 file (smoke from `mix.exs` PR #0.4.14)
├── chunker_test.exs
├── delfos_test.exs
├── elixir_parser_test.exs
├── integration_test.exs
├── reranker_test.exs
├── support/
│   ├── data_case.ex
│   └── factory.ex
├── delfos/
│   ├── cli/
│   │   ├── cli_test.exs
│   │   └── commands/
│   │       ├── audit_test.exs
│   │       ├── config_test.exs
│   │       ├── context_test.exs
│   │       ├── doctor_test.exs
│   │       ├── explain_test.exs
│   │       ├── graph_test.exs
│   │       ├── init_test.exs
│   │       ├── integrate_formats_test.exs
│   │       ├── integrate_test.exs
│   │       ├── models_test.exs
│   │       ├── query_test.exs
│   │       ├── scan_test.exs
│   │       ├── setup_db_test.exs
│   │       ├── setup_llm_test.exs
│   │       ├── setup_test.exs
│   │       ├── status_test.exs
│   │       └── summarize_test.exs
│   ├── integration_test.exs
│   ├── mcp/server_test.exs
│   ├── parsers/dispatcher_test.exs
│   └── syntax/
│       ├── registry_test.exs
│       └── utils_test.exs
```

### 4.3 Coverage gaps

Commands with only `--help` smoke coverage (no positive-path test):
`graph` (`graph_test.exs` has 7 tests, all on `--help` + `fmt/1`
helper + an excluded integration stub), `context`, `status`,
`summarize` (similar shape — helper tests + `--help` + integration
stubs).

Commands with positive-path unit tests: `init`, `scan`, `query`,
`audit`, `explain`, `doctor`, `config`, `integrate`, `models`, `setup`,
`setup/db`, `setup/llm`.

MCP server: covered by `test/delfos/mcp/server_test.exs`
(`build_tool_response + dispatch + timeout`).

Syntax registry: covered by `test/delfos/syntax/registry_test.exs`
(9 tests, every language module + tokenizer smoke).

Parsers dispatcher: covered by `test/delfos/parsers/dispatcher_test.exs`
(13 tests, every extension ↔ language id mapping).

**No test coverage for**: `lib/delfos/health.ex` (only used through
doctor's check layer), `lib/delfos/repo_starter.ex` (new in the
unmerged branch; will need tests when merged — see §6.1),
`lib/delfos/config/manager.ex` (only smoke-tested via doctor).

---

## 5. Known issues

### 5.1 Pre-existing dialyzer warnings (not introduced by 2.0.0)

```
lib/delfos/parsers/dispatcher.ex:90:7:pattern_match_cov
  variable_other can never match — previous clauses completely cover the type
  {:ok, %{docs: [any()], line_count: non_neg_integer(), symbols: [any()], todos: [any()]}}.

lib/delfos/retrieval/hybrid_search.ex:53:8:pattern_match
  Pattern {:ok, %{:result => {:ok, _list}}} can never match the type map().

lib/delfos/retrieval/hybrid_search.ex:54:8:pattern_match
  Pattern {:ok, %{:result => _list}} can never match the type map().
```

All three exist on `main` before our 2.0.0 PR. They are pre-existing
and are listed in §7 as fix candidates. They do not block the 2.0.0
release but should be cleaned up before the next bump.

### 5.2 Pre-existing credo config warnings

```
** (config) Credo.Check.Refactor.Apply: unknown param `force`.
** (config) Ignoring an undefined check: Credo.Check.Refactor.NegatedConditionsInWith.
```

These are warnings from `credo.exs` itself, not from any source file.
`mix credo --strict` reports no issues on the 159 source files.

### 5.3 CLI `serve` fallback is wrong

`lib/delfos/cli.ex:118` — `serve_handler(%{_args: _args})` calls
`Delfos.CLI.Commands.Config.run(["help"])`. This looks like leftover
from an earlier draft (probably `delfos serve` used to launch a config
server before MCP took over). Without `--mcp`, the command should
either print its own `--help` or error out with a clear message.

### 5.4 `--help` / `-h` global flag works by accident

`lib/delfos/cli.ex` does not declare a global `--help` flag handler.
When the user types `delfos --help`, the dispatcher doesn't find a
command named `"--help"` and falls into
`Alaja.CLI.ErrorHandler.unknown_command/2`, which happens to print the
command list. The output is usable but the `Error: unknown command
'--help'` line is noise.

### 5.5 No global `--version` / `-v`

`delfos --version` errors with `Error: unknown command '--version'`.
The user has to know to type `delfos version`. The version is otherwise
correctly resolved via `Delfos.version/0` reading
`Application.spec(:delfos, :vsn)`.

### 5.6 `mix release` binary entry point shows Mix release help

Running `_build/prod/rel/delfos/bin/delfos --help` shows the Mix
release's own help (`start`, `start_iex`, `eval`, `rpc`, …) instead of
the Delfos CLI's help. The Mix release uses `Delfos.CLI` as
`main_module` (per `mix.exs:36` `defp escript, do: [main_module:
Delfos.CLI, name: "delfos"]`), but Mix releases don't honour
`main_module` for the top-level script — they only honour it for
escripts. **The batamanta-bundled binary** (`./delfos` produced by
`mix batamanta`) does invoke `Delfos.CLI.main/1` correctly; the
`_build/prod/rel/...` path is just stale debug output that we should
not be running.

### 5.7 `req` has two open CVEs

`mix deps.get` prints:

```
req 0.5.18 VULNERABLE!
  EEF-CVE-2026-49756 (LOW)    multipart form-data header injection
  EEF-CVE-2026-49755 (HIGH)   decompression bomb DoS via auto-decoded archive
```

Delfos uses `req` for LLM/embedding HTTP calls (`Delfos.LLM.Client`,
`Delfos.Config.Probe`, `Delfos.Health`). We do **not** decode
multipart archives, so CVE-2026-49755 does not affect us in practice,
but the upgrade is still desirable. Tracked in §7.5.

---

## 6. Work already in flight (not merged)

### 6.1 `origin/fix/repo-startup-and-bridge` — 3 commits ahead of `main`

```
f99968d refactor(delfos): remove Apero dep, eliminate handler bridge, fix repo startup
1c2d410 docs(delfos): dedupe CHANGELOG entries, sync versions with tags
785069b refactor(delfos): eliminate handler-bridge anti-pattern, add RepoStarter pre-flight
```

This branch:

- **Removes the Apero runtime dep** entirely (only `Delfos.Config.Probe`
  used `Apero.Network.port_open?/3`).
- **Eliminates the handler-bridge anti-pattern**: each `X_handler/1`
  in `lib/delfos/cli.ex` now calls `Commands.X.run_with_opts(%{…})`
  with the parsed opts map directly, instead of going through
  `build_args/1` → argv string list → re-parse with `OptionParser.parse/2`
  inside `Commands.X.run/1`. Adds `run_with_opts/1` to every command
  module.
- **Adds `Delfos.RepoStarter`**: a GenServer that owns
  `Application.ensure_all_started(:delfos)` + `Ecto.Adapters.SQL.Sandbox.checkout/2`
  pre-flight, so the first command on a fresh DB doesn't race with
  migration application.
- Updates `mix.exs` to drop `apero` from `deps/0`.
- Updates `CHANGELOG.md` and several docs (`CONTRIBUTING.md`,
  `README.md`, `SPEC.md`, `docs/DELFOS-CONTEXT.md`, `docs/HANDOFF.md`,
  `docs/README.es.md`) with the deduped entry.

This work was **not merged into `main` before the 2.0.0 tag**. The
2.0.0 PR (#4) was based on `main` at `df11036`, which doesn't include
these commits. **First action item of the next phase** is to merge
`origin/fix/repo-startup-and-bridge` on top of 2.0.0 (resolving the
CHANGELOG conflict) and cut a 2.0.1. See §7.1.

### 6.2 `origin/m3-delfos-audit` — 1 commit ahead of `main`

```
bb90a4a docs: update CHANGELOG and README for new modules + Registry fix
```

Pure documentation commit. Can be dropped or fast-forwarded — its
content is already subsumed by the 2.0.0 CHANGELOG rewrite. The
`stash@{0}` reference in `git log` indicates a stash was created on
top of this branch (the `50deb4c WIP on m3-delfos-audit` line).

### 6.3 `origin/cleanup/delfos-quality` and `origin/feat/candil-llm-client-v2`

Exist on the remote but have no commits on top of `main` from what
`git ls-remote` shows — they are stale references. Treat them as
informational only.

---

## 7. Phase plan (ordered)

### 7.1 PR #5 — Merge `fix/repo-startup-and-bridge` on top of 2.0.0 → cut 2.0.1

- Branch: `chore/merge-fix-repo-startup-and-bridge` from `main`.
- Merge `origin/fix/repo-startup-and-bridge` into the new branch
  (use `--no-ff` to preserve the 3-commit shape).
- Resolve the `CHANGELOG.md` conflict by:
  - Keeping the new `[2.0.0]` header from main.
  - Adding a new `[2.0.1] - 2026-07-XX` section above it with the
    Apero-dep removal, handler-bridge elimination, and RepoStarter
    additions (lift these from the branch's 1c2d410 commit description).
  - Dropping the now-obsolete "fix(delfos): update batamanta pin" and
    "fix(delfos): fallback batamanta dep from path to git" entries
    that the branch re-adds; these are already covered by main.
- Bump `mix.exs` `@version` `2.0.0` → `2.0.1`.
- Tag HEAD with `2.0.1`, open PR, merge with admin, push tag.
- Acceptance: `mix test`, `mix dialyzer`, `mix credo --strict`, and
  `mix format --check-formatted` all green on `main` (modulo the
  pre-existing dialyzer warnings in §5.1 — these will be fixed in
  §7.2, not §7.1).

### 7.2 PR #6 — Fix the 3 pre-existing dialyzer warnings

- Branch: `fix/delfos-dialyzer-warnings` from `main`.
- Fixes:
  - **`parsers/dispatcher.ex:90`** — read the `variable_other` clause
    and either remove it (if unreachable) or split the head to make
    the union exhaustive.
  - **`retrieval/hybrid_search.ex:53–54`** — the dispatch helper
    pattern-matches on `{:ok, %{result: {:ok, _list}}}` but the
    upstream now returns a bare map (post `Arrea.run_sync/2`
    refactor). Either update the pattern or normalize at the call
    site so dialyzer sees the same shape it sees in the type spec.
- Add the same `@type` annotations where the warnings originate (the
  `result` shape was an alias that the refactor changed).
- Acceptance: `mix dialyzer` reports `done (no warnings were emitted)`.

### 7.3 PR #7 — Global `--help`, `--version`, `-h`, `-v` flags

- Branch: `feat/delfos-cli-global-flags` from `main`.
- Either:
  - (a) Add a pre-dispatch hook in `Delfos.CLI` that intercepts
    `--help`/`-h`/`--version`/`-v` before `Alaja.CLI.Definition.dispatch/2`
    runs. The handler can call `Alaja.CLI.Help.full/0`-equivalent
    using `Delfos.CLI.__commands__()`.
  - (b) Add a `subcommand "help", "Show this help"` and a
    `subcommand "version"` so the existing DSL's "unknown command"
    mechanism still routes them.
- Option (a) is cleaner. Option (b) is less code but requires the
  user to type `delfos help` and `delfos --help` (the latter still
  won't be a global flag).
- Once implemented, fix `serve_handler/1`'s fallback (§5.3) to print
  `Commands.Serve.run(["--help"])` (a new `Delfos.CLI.Commands.Serve`
  module with a `@help` block) instead of `Commands.Config.run(["help"])`.
- Acceptance: `delfos --help`, `delfos -h`, `delfos --version`,
  `delfos -v` all behave correctly. `delfos serve` without `--mcp`
  prints a `serve`-specific help block.

### 7.4 PR #8 — Bring the power-shell + groovy tree-sitter grammars live

- Branch: `feat/tree-sitter-powershell-and-groovy` from `main`.
- The grammars are already in `native/tree_sitter_nif/Cargo.toml`
  (pinned `=0.25.10` and `=0.1.2` respectively) and the Rust bindings
  are wired in `src/lib.rs`. The remaining work is to:
  - Update `parsers/treesitter/tree_sitter.ex#language_for/1` to
    expose `"powershell"` and `"groovy"` instead of routing them to
    the regex `GenericParser`.
  - Update `parsers/dispatcher.ex#language_map` if the NIF atom names
    don't match (probably `"powershell"` → `"powershell"` directly,
    `"groovy"` → `"groovy"` directly).
  - Update `parsers/treesitter/tree_sitter.ex#@supported_languages` to
    include both.
  - Regenerate `Cargo.lock` (requires Rust 1.78+; will be done on the
    user's host, not in the sandbox — Cargo 1.65 is too old).
  - Add tests in `test/delfos/parsers/dispatcher_test.exs` and
    `test/delfos/parsers/treesitter/tree_sitter_test.exs` (the latter
    may need to be created).
- Acceptance: `iex -S mix` → `:ets.tab2list(Delfos.Parsers.TreeSitter.supported_languages())`
  includes `:powershell` and `:groovy`. `mix test
  test/delfos/parsers/` is green.
- Note: this PR needs a host with Rust ≥ 1.78 to actually compile and
  test. The sandbox cannot.

### 7.5 PR #9 — Upgrade `req` to clear the open CVEs

- Branch: `chore/delfos-bump-req` from `main`.
- `mix.exs:68` — `{:req, "~> 0.5"}` → `{:req, "~> 0.5.19"}` (or
  whichever version backports the fix; check `hex.pm/packages/req`).
- Run `mix deps.get`, `mix deps.compile req`, `mix test`.
- Acceptance: `mix deps.get` no longer prints `VULNERABLE!` for
  `req`.

### 7.6 PR #10 — Either enable the skipped dispatcher test or remove it

- Branch: `test/delfos-dispatcher-unsupported-extension` from `main`.
- The test at `test/delfos/integration_test.exs:101` expects
  `Dispatcher.parse("image.png", "...")` to return
  `{:error, :unsupported_extension}`. The current dispatcher routes
  unknown extensions to the regex `GenericParser`, which returns
  `{:ok, %{...}}`. Two options:
  - (a) Change the dispatcher to return `{:error, :unsupported_extension}`
    for known-binary extensions (`.png`, `.jpg`, `.gif`, `.pdf`,
    `.zip`, `.tar`, `.gz`, etc.) and remove the `@tag :skip`. Add a
    small allowlist.
  - (b) Delete the test entirely — the dispatcher's behaviour is
    documented as "fall back to GenericParser" and changing it would
    affect every consumer that parses `.txt`, `.md`, etc. (which are
    also "unknown" but legitimately parseable).
- Recommend (a) with a conservative binary-extension allowlist.
- Acceptance: the test runs (no `@tag :skip`) and passes.

### 7.7 PR #11 — `delfos release --install` step

- Not in scope for 2.x — defer to 3.0.0. The batamanta pipeline
  already covers this via `mix gen`, so the only missing piece is a
  user-facing alias. Defer until the user asks for it.

---

## 8. Open questions / risks

### 8.1 Will the 2.0.0 release binary actually work?

The `_build/prod/rel/delfos/bin/delfos --help` test (§5.6) showed the
Mix release script, not the Delfos CLI. The batamanta-bundled binary
at `./delfos` is the actual delivery artefact. We have not verified
that `./delfos doctor` runs end-to-end on a fresh checkout because
the sandbox lacks a Postgres. This is a **known gap** that the user
accepts (see HANDOFF.md §10).

**Risk**: the user may file a bug if the batamanta binary doesn't
work in their environment. The next session should ask the user to
run `mix gen && ./delfos doctor` and report back.

### 8.2 Is `version: ~> 2.0.0` correct for `alaja`?

The `mix.exs` constraint was set to `{:alaja, "~> 2.0.0", override: true}`
in the 0.4.13 era. After the recent alaja bump to 2.0.0 (botica PR #22 /
candil PR #9), this constraint is satisfied. If alaja cuts 2.0.1 with
bug fixes, delfos will pick it up automatically (which is what we
want — we depend on alaja's CLI DSL). If alaja cuts 3.0.0 with
breaking changes, we'll need to coordinate. Tracked in `mix.exs:57`.

### 8.3 Why isn't the handler-bridge refactor (§6.1) already merged?

The branch was created in an earlier opencode session (`ses_0d0b18da6ffe590mImuo1pgmfO`)
and is sitting on `origin/fix/repo-startup-and-bridge` with 3
ahead-of-main commits. The current session (the one that wrote this
document) merged the 2.0.0 PR first because the user's brief was
explicit about Scenario A — CHANGELOG consolidation + version bump —
before any structural refactor lands. The next session should start
with §7.1.

### 8.4 Are there other opencode sessions I should be aware of?

Two were referenced in the user's brief:
- `ses_0d0b18da6ffe590mImuo1pgmfO` — Phase 0–3 (critical bugs,
  Diagnostics, Probe, doctor refactor, tests).
- `ses_0c965852fffe7L3ofp3ClkbFBR` — batamanta pin cleanup, NIF
  grammar additions, MCP hardening, Syntax.Utils refactor, CLI test
  suite.

Neither session is directly accessible from this one. The commit
history is the canonical record of what they did.

### 8.5 Will the user's tests against a real Postgres pass?

The integration tests (`@tag :integration`) are currently expected to
fail in the sandbox and pass in CI. CI runs them against
`pgvector/pgvector:pg16` (`.github/workflows/ci.yml:54–118`). If the
user reports integration failures locally after pulling this PR, the
fix is almost certainly in their `config/config.exs` (wrong DB host /
credentials), not in the code.

---

## 9. Acceptance criteria for "delfos is ready for 2.1.0 / 3.0.0"

(Drop the version number you don't need. The user's brief used
"v2.0.0 release" but we already tagged 2.0.0; this is the criteria
for the **next** release.)

All of the following must be true on `main` before tagging 2.1.0:

### 9.1 CI green
- [ ] `mix format --check-formatted` clean.
- [ ] `mix credo --strict` clean.
- [ ] `mix test` — 179+ tests, 0 failures, 0 skipped (the 2
  `@tag :skip` tests are resolved per §7.6 and §4.1).
- [ ] `mix test --include integration` — 179+ tests, 0 failures, on
  a host with Postgres.
- [ ] `mix dialyzer` — 0 warnings (the 3 pre-existing ones fixed per
  §7.2).

### 9.2 Code health
- [ ] No new `TODO`, `FIXME`, `XXX`, `HACK` markers in `lib/` (the
  existing TODO/FIXME regex matches in `parsers/*` and
  `analysis/coupling_analyzer.ex` are features, not debt — leave
  them).
- [ ] No `System.halt/1` calls outside of `lib/delfos/cli.ex` (the
  exception is documented in HANDOFF.md §8.3; consolidate to a
  single helper if more appear).
- [ ] No `path: "../<lib>"` in committed `mix.exs` deps (the
  `batamanta_dep/0` switch is allowed; other deps must be
  `github: + branch: "main"`).

### 9.3 Tags and CHANGELOG
- [ ] Latest tag is `2.1.0` (or whatever the version is).
- [ ] `mix.exs` `@version` matches the tag.
- [ ] `CHANGELOG.md` has a `[2.1.0] - YYYY-MM-DD` section above
  `[2.0.0]`.
- [ ] `CHANGELOG.md` `[2.0.0]` section matches what's on the tag.
- [ ] No dangling link footers (`v0.x.y` references — these should
  have been removed in the 2.0.0 PR but verify).

### 9.4 Release binary
- [ ] `mix gen` produces a working `./delfos` binary.
- [ ] `./delfos doctor` returns clean (against the user's Postgres).
- [ ] `./delfos version` prints `delfos 2.1.0`.
- [ ] `./delfos --help`, `./delfos -h`, `./delfos --version`,
  `./delfos -v` all work (§7.3).

### 9.5 Documentation
- [ ] `README.md` mentions the latest release version.
- [ ] `docs/README.es.md` is in sync.
- [ ] `SPEC.md` §20 has an entry for the new release.
- [ ] `CONTRIBUTING.md` doesn't reference deprecated patterns
  (escript releases, `path:` deps, manual handler bridges).

### 9.6 Security
- [ ] `mix deps.get` does not print `VULNERABLE!` for any direct dep
  (§7.5).

---

## 10. Critical paths cheat-sheet

For a fresh agent that needs to jump straight in:

| Need to… | Look at |
|---|---|
| Add a new CLI command | `lib/delfos/cli.ex` (add `command "name", "desc" do … end`), `lib/delfos/cli/commands/<name>.ex` (new module), `lib/delfos/cli/commands/<name>_test.exs` |
| Add a new MCP tool | `lib/delfos/mcp/server.ex#build_tool_response/1`, `lib/delfos/mcp/tools.ex` |
| Add a new tree-sitter grammar | `native/tree_sitter_nif/Cargo.toml`, `native/tree_sitter_nif/src/lib.rs`, `lib/delfos/parsers/treesitter/tree_sitter.ex`, `lib/delfos/parsers/dispatcher.ex` |
| Add a new syntax highlight module | `lib/delfos/syntax/<lang>.ex` (model on existing 70), `lib/delfos/syntax/registry.ex#register_all/0` |
| Add a new Ecto migration | `priv/repo/migrations/<timestamp>_<name>.exs` |
| Add a new dep | `mix.exs` `defp deps do` (preserve the ecosystem pinning rules) |
| Bump the version | `mix.exs` `@version` + `CHANGELOG.md` `[X.Y.Z]` entry + `git tag -a X.Y.Z` |
| Run the full quality gate locally | `mix quality` (see `mix.exs:108–116`) |
| Build the release binary | `mix gen` → produces `./delfos` + installs in `~/bin/delfos` |

---

## 11. End

If you've read this document end-to-end, you have:

1. The current state of `delfos` (post-2.0.0 tag).
2. What works, what is in flight, what is broken.
3. The full dep tree and why each pin is what it is.
4. The test status and where the gaps are.
5. A concrete 6-PR plan (7.1–7.6) for the next release.
6. Open questions and risks.
7. Acceptance criteria for the next release.

The first action item is **§7.1**: merge `origin/fix/repo-startup-and-bridge`
on top of `main`, resolve the CHANGELOG conflict, cut 2.0.1.

Buena suerte en la nueva sesión.