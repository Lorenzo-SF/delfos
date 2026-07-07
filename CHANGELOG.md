# Changelog

All notable changes to Delfos will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [2.1.0] - 2026-07-07

### Added

- **Global `--help`/`--version` flags**. `delfos --help` / `-h` renders
  the full command list via Alaja components (Header, Table, Separator).
  `delfos --version` / `-v` prints the installed version. These intercept
  before the DSL dispatcher, so they work even without a subcommand.
  (PR #7)
- **`Delfos.CLI.Commands.Serve` module**. `delfos serve` without `--mcp`
  now shows serve-specific help instead of falling through to config help.
  (PR #7)
- **PowerShell + Groovy AST parsing via tree-sitter**. 4 new extensions
  in the dispatcher (`.psd1`, `.gvy`, `.gy`, `.gsh`) and full NIF-backed
  symbol extraction for PowerShell (`function`) and Groovy
  (`function_definition`, `method`, `class_definition`). Both grammars
  were pre-wired in the Rust crate (pinned `=0.25.10` and `=0.1.2`) but
  not exposed in the Elixir wrapper. (PR #8)
- **Binary extension allowlist**. 60+ known binary/opaque extensions
  (images, archives, binaries, fonts, media) now return
  `{:error, :unsupported_extension}` from `Dispatcher.parse/2` instead of
  falling through to the regex GenericParser. (PR #10)

### Changed

- **`req` bumped `~> 0.5` → `~> 0.6`** with `override: true` to clear
  2 CVEs (multipart header injection, decompression bomb DoS). Transitive
  finch, mint, and hpax also upgraded. `mix deps.get` no longer reports
  `VULNERABLE!`. (PR #9)
- **`Delfos.Parsers.Dispatcher.parse/2`** now returns `{:error, …}` from
  binary extensions using `with/else` instead of a bare `{:ok, parsed} =`
  match, so the error tuple propagates correctly. (PR #10, side effect)

### Fixed

- **3 pre-existing dialyzer warnings** (`pattern_match_cov` / `pattern_match`):
  `dispatcher.ex` unreachable `other` clause, `hybrid_search.ex` incorrect
  `{:ok, …}` wrapper patterns, and `mcp/tools.ex` dead-case `_ -> []`.
  (PR #6)
- **`Delfos.Parsers.TreeSitter.normalize_lang/1`** no longer routes
  `"powershell"` to `"bash"` — it now correctly maps to `"powershell"`,
  enabling real AST parsing via the NIF. (PR #8)
- **`Delfos.CLI.serve_handler/1`** fallback now calls
  `Commands.Serve.run(["--help"])` instead of `Commands.Config.run(["help"])`.
  (PR #7)

### Tests

- New tests for global flags `--help`/`-h`/`--version`/`-v` (PR #7).
- Unsupported-extension test enabled (was `@tag :skip`) — verifies
  `Dispatcher.parse("image.png")` returns `{:error, :unsupported_extension}`
  (PR #10).

## [2.0.0] - 2026-07-07


### Added

- **CLI migrated to `Alaja.CLI.Definition` DSL**. New module
  `Delfos.CLI` (replacing `Delfos.CLI.Main`) declares every
  subcommand declaratively with `command "name" "description" do ... end`.
  The 192-line manual dispatcher is gone; each
  `Delfos.CLI.Commands.X.run/1` is wired through a thin handler bridge
  to the existing legacy call signature. The escript `main_module` is
  now `Delfos.CLI`. 13 subcommands declared in
  `lib/delfos/cli/commands/`. `test/delfos/cli/cli_test.exs` covers
  `__commands__/0`, help routing, and unknown-command errors.
- **`delfos setup`** wizard with `db` and `llm` sub-flows. Guides the
  user through Postgres install (Docker/apt/brew/existing), remote
  PostgreSQL connection (host:port/user/password, with input hidden
  and 15s connectivity probe), DB creation, `pgvector` verification,
  and migration. The `llm` flow selects between llama.cpp, Ollama
  (with per-OS auto-install: `curl|sh` on Linux/macOS, `brew --cask
  ollama` if brew is available, `winget install Ollama.Ollama` on
  Windows, plus detached-spawn + 30s readiness probe), OpenAI, and
  Anthropic. Subcommands `delfos setup db` and `delfos setup llm` skip
  the top-level menu and jump straight to their wizard.
- **`delfos doctor`** rewritten on top of `Botica.Doctor`. Adds
  `--interactive` (ask before each fix), `--db-only` / `--llm-only`
  filters, and `--json` for machine-readable output. Detects
  `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASS` overrides and reports
  the actual target host. Output is grouped into `[Postgres]
  [TreeSitter] [Models] [Config]` sections with ✓/⚠/✗ icons;
  Postgrex connection-error spam is hidden unless the user asks for
  verbose. After the diagnostic, post-checks inspect failed checks
  and point the user at the right setup wizard.
- **`delfos models`** shows the active embedding and LLM providers
  with masked API keys and the index column dimension. With `--probe`
  it pings each endpoint and reports latency plus dim-mismatch
  warnings. Validates `embedding.dim` config against the actual
  `symbols.embedding` column dimension in PostgreSQL.
- **`Delfos.Health`** — periodic health check that pings the embedding
  and LLM endpoints and reports latency + dim mismatch warnings.
- **`delfos integrate <agent>`** for `claude-code`, `opencode`,
  `cursor`, `aider`, `codex`, `zed`, and `all`. Defensive
  `read_json_or_empty/1` and `verify_json/1` round-trip every write so
  bad JSON in `~/.claude.json`, `~/.config/opencode/config.json`, etc.
  fails loudly instead of silently overwriting. `safe_write/2` backs
  up the existing version to `<path>.bak-<unix_seconds>` before any
  merge.
- **Global `--help` and `-h`** for `delfos` and every subcommand.
  Each help block lists flags, arguments, and worked examples.
- **Tree-sitter NIF: 12 more languages wired in** (was 27 dead
  grammars in `Cargo.toml` — only 18 of them were reachable from
  `lib.rs#language_for/1`). The live NIF set is now 30, with full
  symbol extraction for all of them:

  | Language    | Dispatcher id | NIF atom | Symbol kinds extracted                          |
  |-------------|---------------|----------|--------------------------------------------------|
  | R           | `r`           | `r`      | function                                         |
  | Haskell     | `haskell`     | `haskell`| function (bind), type (data/newtype), trait      |
  | Erlang      | `erlang`      | `erlang` | function, module/struct/type (via -attr)         |
  | OCaml       | `ocaml`       | `ocaml`  | function, type, module, class                   |
  | Clojure     | `clojure`     | `clojure`| (AST parsed; zero symbols — see note below)      |
  | Zig         | `zig`         | `zig`    | function, struct, enum                           |
  | Gleam       | `gleam`       | `gleam`  | function, type                                   |
  | Julia       | `julia`       | `julia`  | function, module, struct                        |
  | Kotlin      | `kotlin`      | `kotlin` | class, method (via community fork `tree-sitter-kotlin-ng`) |
  | Objective-C | `objective-c` | `objc`   | class, method, protocol                         |
  | Assembly    | `assembly`    | `asm`    | label                                            |
  | F#          | `fsharp`      | `fsharp` | function, type, class, module                   |

  Clojure is wired through the NIF for AST-based parsing (replacing
  the regex fallback) but its grammar has no distinct function/class
  nodes — everything is `list_lit`. Returns zero symbols from
  `extract_symbols`; this matches the existing pattern for
  bash/c/cpp/php/ruby/swift/dart/scala/lua which are also AST-parsed
  but symbol-extracted by the regex GenericParser in the fallback
  path. Future work: semantic extraction from `list_lit` children.

- **`tree-sitter-kotlin-ng`** added to `Cargo.toml` — the upstream
  `tree-sitter-kotlin` does not target tree-sitter 0.25, so the
  grammar was missing entirely from the NIF. The community fork is
  ABI-compatible and matched against the existing
  `(l, "class_declaration") if matches!(l, "java" | "kotlin" |
  "csharp")` and `(l, "method_declaration")` extraction branches.
- **Syntax highlighting modules** for `assembly.ex`, `fsharp.ex`,
  `vb.ex` (the three languages in `syntax/` that were missing from
  the registry — `lib/delfos/syntax/registry.ex#languages/0`). All
  70 syntax modules are registered at `Application.start/2`.
- **`normalize_lang/1` aliases**: dispatcher's canonical `objective-c`
  and `assembly` are mapped to NIF atoms `objc` and `asm`
  respectively, so the dispatcher's `language_map` stays
  human-readable while the NIF uses short ids.
- **`Delfos.Syntax.Utils`** — shared helpers used by `explain`,
  `audit`, and `query`: `safe_to_atom/1` for language detection and
  `detect_lang_atom/1` for the dispatcher id.
- **HNSW indexes** on `chunks.embedding` and `symbols.embedding` for
  faster vector queries.
- **`config/runtime.exs`** — production-only env-var validation.
- **Graceful shutdown** (`Application.stop`).
- **Defensive `Jason.encode` (no `!`)** in the MCP server, removing
  the risk of an unhandled exception in the middle of a JSON-RPC
  reply.
- **MCP server async stdin reader** — replaced `after: 0` polling
  with an async stdin reader to fix the spin-loop.
- **MCP tool timeout + try/rescue around dispatch** so a slow tool
  cannot stall the JSON-RPC loop.
- **GraphBuilder N+1 fix**: preloads files into a lookup map instead
  of one query per node.
- **Code highlighting** in `query` result snippets.
- **`mix gen`** — a one-shot Mix task (`lib/mix/tasks/gen.ex`) that
  builds the release end-to-end and handles every platform-specific
  quirk:
  - Detects OS (mac, debian/ubuntu, fedora/rhel, arch, windows,
    other-linux) and reports missing toolchain (`rustc < 1.78`, no
    `cc`, no `cmake`) with the exact install command for that
    distribution.
  - Writes `native/tree_sitter_nif/.cargo/config.toml` if missing,
    so macOS links the tree-sitter NIF with the right
    `dynamic_lookup` rustflag — without per-machine setup. Users who
    cloned the repo before v0.4.10 now get a working build
    automatically.
  - Runs `mix deps.get` if `deps/` is missing.
  - Compiles, releases, deploys to `~/bin/delfos`, writes the
    `.tool-versions` file.
  - Prints a single concise "what to do next" line so the user never
    has to grep through the build log.
  - Honors `--no-deploy` for users who just want the release
    directory without copying it anywhere.
- **Test coverage**: tests for the dispatcher
  (`test/delfos/parsers/dispatcher_test.exs`, 13 tests verifying every
  shipped code extension and tree-sitter language id), the syntax
  registry (`test/delfos/syntax/registry_test.exs`, 9 tests
  validating every `definition/0`), and command-level tests for
  `init`, `scan`, `query`, `audit`, `explain`, `context`, `status`,
  `summarize`, `graph`, `setup`, `setup/db`, `setup/llm`, plus MCP
  server tests (`build_tool_response` + dispatch + timeout).

### Changed

- **Build switched from `escript` to Mix release** (`format: :release`
  in `mix.exs` `batamanta/0`). Required because `escript` cannot
  embed Rust NIFs (tree-sitter) — the previous `escript` config
  silently dropped `libtree_sitter_nif.so` at bundle time, so the
  resulting binary crashed with `cannot open shared object file` and
  fell back to the regex `GenericParser`.
- **Config migrated from TOML to JSON**. `~/.config/delfos/delfos.conf`
  is no longer used; the new path is `~/.config/delfos/config.json`.
  API keys are encrypted at rest with AES-256-GCM via
  `Apero.Crypto.Cipher` and decrypted lazily on read. The encryption
  key lives in `~/.config/delfos/.key`. Environment variables
  (`DB_HOST`, `DB_PASSWORD`, `EMBED_URL`, `LLM_MODEL`, etc.) still
  take precedence.
- **Tree-sitter bumped to 0.25** (removes Kotlin grammar support
  from the upstream 0.25 grammars; re-added via the
  `tree-sitter-kotlin-ng` community fork above).
- **`Delfos.version/0`** now reads from the loaded application spec
  (`Application.spec(:delfos, :vsn)`) instead of returning a hardcoded
  string.
- **`mix.exs` deps pinned to `github:` + `branch: "main"`** for every
  Lorenzo-SF ecosystem dep (`alaja`, `candil`, `arrea`, `apero`,
  `botica`). Pinning to a tag used to ship stale SHAs:
  - `pote` v0.2.0 had no `Pote.Theme`.
  - `candil` v0.2.0 had no `Provider` struct.
  - `alaja` v0.3.8 had a `question_with_options/3` that broke
    `delfos setup` (only matched exact labels; v0.3.12 accepts
    1-based indexes, atom names, and case-insensitive prefixes).
  Tracking `main` is a faster feedback loop: a breaking change
  upstream breaks our build immediately, instead of silently shipping
  a frozen bug.
- **`delfos doctor` reports by section** — the previous flat list
  with Postgrex flooding the output is replaced by `[Postgres]
  [TreeSitter] [Models] [Config]` sections, one row per check with a
  ✓/⚠/✗ icon.
- **`mix docs`** no longer fails because `README_ES.md` was missing
  — the `extras:` list now points to `docs/README.es.md`.
- **`delfos integrate`** reads existing JSON files defensively
  (`read_json_or_empty/1`) and verifies each write with `verify_json/1`.
- **`delfos integrate aider`** no longer overwrites an existing
  `AGENTS.md` without warning; if Delfos instructions are not already
  present, the file is backed up to `AGENTS.md.bak-<unix_ts>` before
  the merge.
- **Postgrex errors** are surfaced through `format_db_error/1` and
  `format_error/1` helpers instead of raw `inspect/1`. Errors in
  `delfos query`, `delfos doctor`, etc. now include a "next step"
  hint pointing to `delfos doctor` or `delfos models`.
- **`mix.exs` adds `docs` (groups_for_modules), `dialyzer_config`,
  and `CHANGELOG.md` extras**. The release `applications:` list now
  marks `candil: :transient` (it owns a long-running engine that we
  don't want supervised as `:permanent`).

### Fixed

- **NIF included in the released binary** — batamanta had
  `format: :escript` in `mix.exs`, which silently drops Rust NIFs
  from the bundle. Changed to `format: :release` so
  `libtree_sitter_nif.so` ships with the final binary.
- **`delfos setup db` auto-migrate now works in the release binary**:
  - `setup/db.ex#apply_migrations` previously used
    `Code.eval_string/1` which DOES NOT work for
    `use Ecto.Migration` scripts (those need to be invoked through
    `Ecto.Migrator`). Replaced with `Ecto.Migrator.run/4`, the
    canonical helper that handles schema diffing and migration
    bookkeeping in `schema_migrations`.
  - `Application.start/2` now launches a Task that runs the same
    `Ecto.Migrator.run(:up, all: true)` on every boot. The release
    ships `priv/repo/migrations/` next to its bin (added a
    `copy_priv/1` step in `mix.exs`), so the first command the user
    runs already finds the schema up to date.
  - `setup/db.ex#apply_migrations` switched from
    `Code.eval_string/1` to `Ecto.Migrator.with_repo/3`.
- **`delfos setup db` auto-installs pgvector via the Repo** instead
  of shelling out to `psql`. The release binary doesn't ship `psql`
  in its PATH, so the previous fallback failed silently. Now
  `install_pgvector/0` runs `CREATE EXTENSION IF NOT EXISTS vector`
  over the existing TCP connection.
- **`prod.exs` default DB name** changed from `delfos_prod` to
  `delfos_dev`. Now `mix gen` under `MIX_ENV=prod` produces a binary
  that talks to the same database as dev, by default. Override with
  `DB_NAME=production` env var when actually deploying.
- **`delfos setup db` Docker container conflict** — if a stopped
  container with the same name exists, the wizard now asks what to
  do (remove / keep / rename) instead of letting `docker run` fail
  with `Conflict. The container name ... is already in use`.
- **`Ecto.Migrator.run/4` called incorrectly** — passing
  `[{path, []}]` (tuples) tripped a `dynamic(...)` typing warning in
  `mix compile --warnings-as-errors`. Switched to the canonical
  `Ecto.Migrator.with_repo/3` wrapper used by `mix ecto.migrate`
  itself, with plain `paths :: [String.t()]` as second arg.
- **Postgres 17 in the Docker suggestion** — both
  `setup/db.ex#setup_docker` and the doctor help text now reference
  `postgres:17` instead of `postgres:16`. pgvector 0.4.0 (the current
  lock) supports Postgres 13–17 officially. Postgres 18 needs an
  update to pgvector 0.8+ which isn't on Hex yet.
- **macOS build** — added
  `native/tree_sitter_nif/.cargo/config.toml` with the
  `link-arg=-undefined` + `link-arg=dynamic_lookup` rustflags Rustler
  needs to compile NIFs on macOS. Previously
  `MIX_ENV=prod mix release` (or `mix gen`) raised
  `Rustler.Compiler.ensure_platform_requirements!/3` on Mac users.
- **Repo unavailable error on every command** — `mix gen` produced a
  release where `delfos init`/`scan`/`query`/`audit`/`summarize`
  crashed with `could not lookup Ecto repo Delfos.Repo because it
  was not started`. The release uses `include_erts: false` so the
  host OTP application never started. `mix gen` now delegates to
  `mix release --overwrite`, which wires up the start-permanent
  flag correctly, AND `Alaja.CLI.Definition.dispatch_main/1` now
  calls `Application.ensure_all_started(__otp_app__())` so the
  supervisor tree is up before any command runs.
- **`@doc` above `defp maybe_suggest_setup/2`** in `delfos doctor`
  was dropped — Elixir 1.19 emits a warning when a private function
  is decorated with `@doc` (the doc is silently discarded).
- **`delfos doctor` no longer references the non-existent
  `Apero.Doctor`** — rewritten on top of `Botica.Doctor`.
- **Codex** was writing YAML to `~/.codex/config.yaml` with key
  `mcp_servers:`. The real format is **TOML** at
  `~/.codex/config.toml` with key `[mcp_servers]`. Switched and
  added round-trip validation via `Toml.decode_file/1`.
- **Cursor** was writing to `.cursorrules` (deprecated in Cursor
  0.45+). Switched to `.cursor/rules/delfos.mdc` with YAML
  frontmatter.
- **Aider** was appending `read:\n  - AGENTS.md` to `.aider.conf.yml`,
  producing a second `read:` block (invalid YAML). Now parses the
  existing config with `YamlElixir`, merges the new entry into the
  existing `read:` list, and rewrites.

### Removed

- **`lib/delfos/cli/commands/main.ex`** — replaced by `Delfos.CLI`.
- **`yaml_elixir ~> 2.11`** runtime dep — `merge_aider_read/1` was
  switched to a regex-based approach (Elixir 1.17+ compatibility)
  and the dep is no longer needed.
- **`Apero.Llm.*` references** — `Apero.Llm.Health` was the only
  consumer in delfos; replaced with `Candil.Health.ping/3`. The
  module belongs in Candil (the LLM domain), not Apero.
- **Dangling `v0.2.0` / `v0.3.0` tags** — never existed in this
  repo; the CHANGELOG link footers now point only at `1.0.0` and
  `2.0.0`.

### Deferred (still falling back to regex GenericParser)

- **`powershell`, `groovy`** — both grammars' latest published
  versions (0.26.4 and 0.1.2 respectively) require
  `tree-sitter ^0.26`. The crate is pinned to 0.25 to keep the rest
  of the NIF stable. Syntax highlighting still works via
  `Delfos.Syntax.PowerShell` and `Delfos.Syntax.Groovy`. Until a
  0.25-targeted release is available upstream, parsing stays on the
  regex fallback. See the new comment block in `Cargo.toml` for the
  full rationale.
- **`perl`** — same ABI conflict, already excluded earlier.
- **`vb`** — no `tree-sitter-vbnet` crate published on crates.io.
  Regex fallback + syntax highlighting via `Delfos.Syntax.Vb`.

### Caveats

- The NIF cannot be recompiled in the dev sandbox (Cargo 1.65 from
  Debian is too old for tree-sitter 0.25). `Cargo.lock` was not
  regenerated against the new `Cargo.toml` — the first `mix compile`
  on a host with Rust ≥ 1.78 will pull the new grammar crates and
  update `Cargo.lock` accordingly.
- Existing NIF languages (bash/c/cpp/php/ruby/swift/dart/scala/lua)
  are still AST-parsed with no symbol extraction. Same tradeoff as
  Clojure — not addressed in this release to keep the diff scoped.

## [1.0.0] - 2026-06-10

### Added
- Initial open source release: MCP server (JSON-RPC 2.0 over stdio,
  protocol version 2024-11-05) with 8 tools, hybrid search (vector +
  BM25 + graph) via Reciprocal Rank Fusion, `CandilBridge` adapter so
  OpenAI-compatible chat/embed calls route through `Candil` when
  available, and `delfos integrate <agent>` for `claude-code`,
  `opencode`, `cursor`, `aider`, `codex`, `zed` and `all`.

[2.0.0]: https://hex.pm/packages/delfos/2.0.0
[1.0.0]: https://hex.pm/packages/delfos/1.0.0


> ## A note on versioning
>
> The only canonical tags are `1.0.0` (initial open-source cut-over)
> and `2.0.0` (current HEAD). The `[0.2.0]` … `[0.4.19]` headers in
> earlier drafts were **planning milestones**, not releases: they
> have no corresponding git tags. Earlier `0.x` versions are no
> longer maintained and have been collapsed into this single
> canonical `2.0.0` entry. `mix.exs` `version` reflects the current
> development state and may be ahead of the public surface. Pin to
> `1.0.0` or `2.0.0` for stable dependencies.

> ## A note on history
>
> The git history of this repository was rewritten as part of a
> deliberate cleanup effort. The commits you can read describe the
> codebase as it stands today — they do not preserve the original
> chronology of development.
>
> Anything worth keeping from before the rewrite was carried forward
> as tagged releases with explicit `CHANGELOG.md` entries. Anything
> not preserved is, by the maintainer's choice, no longer part of the
> canonical development line.
>
> Tag `1.0.0` points to the initial open-source cut-over; tag
> `2.0.0` points to the current HEAD and the canonical consolidated
> release. All versioned artifacts on Hex.pm and GitHub Releases
> follow this convention.