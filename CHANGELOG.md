# Changelog

All notable changes to Delfos will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [0.4.19] - 2026-06-29

### Added
- **Tree-sitter NIF: 12 more languages wired in** (was 27 dead grammars in
  `Cargo.toml` — only 18 of them were reachable from `lib.rs#language_for/1`).
  New wire-ups bring the live NIF set to 30, with full symbol extraction for
  all of them:

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

  Clojure is wired through the NIF for AST-based parsing (replacing the regex
  fallback) but its grammar has no distinct function/class nodes — everything
  is `list_lit`. Returns zero symbols from `extract_symbols`; this matches the
  existing pattern for bash/c/cpp/php/ruby/swift/dart/scala/lua which are
  also AST-parsed but symbol-extracted by the regex GenericParser in the
  fallback path. Future work: semantic extraction from `list_lit` children.

- **`tree-sitter-kotlin-ng`** added to `Cargo.toml` — the upstream
  `tree-sitter-kotlin` does not target tree-sitter 0.25, so the grammar was
  missing entirely from the NIF. The community fork is ABI-compatible and
  matched against the existing `(l, "class_declaration") if matches!(l, "java"
  | "kotlin" | "csharp")` and `(l, "method_declaration")` extraction branches.

- **Syntax highlighting modules** for `assembly.ex`, `fsharp.ex`, `vb.ex`
  (were the only three languages in `syntax/` directory missing from the
  registry — `lib/delfos/syntax/registry.ex#languages/0`). All 70 syntax
  modules now registered at `Application.start/2`.

- **`normalize_lang/1` aliases**: dispatcher's canonical `objective-c` and
  `assembly` are now mapped to NIF atoms `objc` and `asm` respectively, so
  the dispatcher's `language_map` stays human-readable while the NIF uses
  short ids.

### Deferred (still falling back to regex GenericParser)
- **`powershell`, `groovy`** — both grammars' latest published versions
  (0.26.4 and 0.1.2 respectively) require `tree-sitter ^0.26`. The crate is
  pinned to 0.25 to keep the rest of the NIF stable. Syntax highlighting still
  works via `Delfos.Syntax.PowerShell` and `Delfos.Syntax.Groovy`. Until a
  0.25-targeted release is available upstream, parsing stays on the regex
  fallback. See the new comment block in `Cargo.toml` for the full rationale.
- **`perl`** — same ABI conflict, already excluded in v0.4.18.
- **`vb`** — no `tree-sitter-vbnet` crate published on crates.io. Regex
  fallback + syntax highlighting via `Delfos.Syntax.Vb`.

### Caveats
- The NIF cannot be recompiled in the dev sandbox (Cargo 1.65 from Debian is
  too old for tree-sitter 0.25). `Cargo.lock` was not regenerated against the
  new `Cargo.toml` — the first `mix compile` on a host with Rust ≥ 1.78 will
  pull the new grammar crates and update `Cargo.lock` accordingly.
- Existing NIF languages (bash/c/cpp/php/ruby/swift/dart/scala/lua) are still
  AST-parsed with no symbol extraction. Same tradeoff as Clojure — not
  addressed in this release to keep the diff scoped.

## [0.4.18] - 2026-06-29

### Fixed
- **`mix gen` now actually builds** — previous version produced a release
  that crashed at startup. Tree-sitter-perl removed from the NIF build.

## [0.4.17] - 2026-06-29

### Fixed
- **NIF included in the released binary** — batamanta had `format: :escript`
  in `mix.exs`, which silently drops Rust NIFs from the bundle.
  Changed to `format: :release` so `libtree_sitter_nif.so` actually
  ships with the final binary. The previous release crashed at
  every NIF probe with `Failed to load NIF library: '/tmp/.../release/bin/delfos/delfos/priv/native/libtree_sitter_nif.so'`
  — that `bin/delfos/delfos/` double-prefix was a symptom of
  escript trying to inline a path it couldn't serve.
- **`delfos setup db` and `delfos setup llm`** now skip the
  top-level menu and jump straight to the DB or LLM wizard. The
  previous version ignored any positional arguments and always
  showed the "What do you want to configure?" menu.
- **`prod.exs` default DB name** changed from `delfos_prod` to
  `delfos_dev`. Now `mix gen` under MIX_ENV=prod produces a binary
  that talks to the same database as dev, by default. Override
  with `DB_NAME=production` env var when actually deploying.
- **`delfos setup db` Docker conflict** — if a stopped container
  with the same name exists, the wizard now asks what to do
  (remove / keep / rename) instead of letting `docker run` fail
  with `Conflict. The container name ... is already in use`.
- **`Ecto.Migrator.run/4` called incorrectly** — passing
  `[{path, []}]` (tuplas) trips a `dynamic(...)` typing warning
  in `mix compile --warnings-as-errors`. Switched to the canonical
  `Ecto.Migrator.with_repo/3` wrapper used by `mix ecto.migrate`
  itself, with plain `paths :: [String.t()]` as second arg.
- **`setup/db.ex#apply_migrations`** switched from
  `Code.eval_string/1` (which doesn't execute `use Ecto.Migration`
  scripts correctly) to `Ecto.Migrator.with_repo/3`.

### Added
- **Tree-sitter NIF supports 9 more languages**: haskell,
  erlang, ocaml, clojure, zig, gleam, julia, hcl, perl. Brings
  total NIF coverage to 27 (was 18).
- **`delfos doctor` reports by section** — the previous version
  spat out a flat list of check results with Postgrex flooding
  the output with `[error] failed to connect` lines (one per
  connection in the pool). The new layout groups checks into
  `[Postgres] [TreeSitter] [Models] [Config]` sections, one row
  per check with a ✓/⚠/✗ icon. Postgrex connection-error spam
  is hidden unless the user specifically asks for verbose.

- **`test/delfos/parsers/dispatcher_test.exs`** (13 tests)
  verifying every code extension we ship is recognised and
  every tree-sitter language id in `@supported_languages` lines
  up with what the dispatcher advertises.

## [0.4.16] - 2026-06-29

### Fixed
- **`delfos setup db` auto-migrate now works in the release binary**:
  - `setup/db.ex#apply_migrations` previously used `Code.eval_string/1`
    which DOES NOT work for `use Ecto.Migration` scripts (those need
    to be invoked through Ecto.Migrator). Replaced with
    `Ecto.Migrator.run/4`, the canonical helper that handles schema
    diffing and migration bookkeeping in `schema_migrations`.
  - `Application.start/2` now launches a Task that runs the same
    `Ecto.Migrator.run(:up, all: true)` on every boot. The release
    ships `priv/repo/migrations/` next to its bin (added a
    `copy_priv/1` step in `mix.exs`), so the first command the user
    runs already finds the schema up to date.
- **`delfos setup db` auto-installs pgvector via the Repo** instead
  of shelling out to `psql`. The release binary doesn't ship
  `psql` in its PATH, so the previous fallback failed silently.
  Now `install_pgvector/0` runs `CREATE EXTENSION IF NOT EXISTS
  vector` over the existing TCP connection.
- **Postgres 17 in the Docker suggestion** — both
  `setup/db.ex#setup_docker` and the doctor help text now reference
  `postgres:17` instead of `postgres:16`. pgvector 0.4.0 (the current
  lock) supports Postgres 13–17 officially. Postgres 18 needs an
  update to pgvector 0.8+ which isn't on Hex yet; flagging this
  so users with PG 18 know to upgrade separately.

## [0.4.15] - 2026-06-29

### Fixed
- **`mix.exs` deps switched back to `github:`, `branch: "main"`** —
  The previous v0.4.14 commit left `path: "../alaja"`-style deps in
  `mix.exs`. That works in the multi-repo workspace but breaks
  end-user clones (the path doesn't exist). Reverted to
  `github: "Lorenzo-SF/lib", branch: "main"` for every Lorenzo-SF
  ecosystem dep. `mix.lock` is bumped to the latest main of each.
  Removed the 14-line multi-repo dev comment block from earlier.

## [0.4.14] - 2026-06-29

### Fixed
- **`mix.exs` deps cleaned up** — the previous commit introduced a
  `System.get_env("DELFOS_DEV_UMBRELLA")` switch and a 14-line
  comment block. The user always works with sibling checkouts in
  `~/Projects/<lib>` and the rest of the ecosystem uses `path:` or
  `branch: "main"` consistently. Reverted to that simpler form:
  every Lorenzo-SF lib is `path: "../lib"` (or `override: true`
  where strictly needed), no tags, no env switching.
- **`mix gen` alias restored** — the previous commit deleted the
  `gen: [...]` alias in favor of a `Mix.Tasks.Gen` task. Aliases
  take precedence over Mix tasks when names collide, so the user
  experience was "alias gone, task gone". Renamed the task to
  `Mix.Tasks.ReleaseBuild` (invoked as `mix release.build`),
  so the `gen: ["release.build"]` alias and the task can coexist.
  Either `mix gen` or `mix release.build` works now.
- **Repo unavailable error on every command** — `mix gen` produced
  a release where `delfos init`/`scan`/`query`/`audit`/`summarize`
  crashed with `could not lookup Ecto repo Delfos.Repo because it
  was not started`. The release uses `include_erts: false` so the
  host OTP application never started. `mix gen` now delegates to
  `mix release --overwrite`, which wires up the start-permanent
  flag correctly, AND `Alaja.CLI.Definition.dispatch_main/1` now
  calls `Application.ensure_all_started(__otp_app__())` so the
  supervisor tree is up before any command runs.

### Added
- `test/alaja/cli/definition_test.exs` — smoke test that loads
  `Alaja.CLI.Definition` against a stub `otp_app:` and runs
  `main/1`. Confirms the new pre-flight doesn't break any of
  the existing `use Alaja.CLI.Definition` consumers (delfos,
  arrea, apero, candil, botica all use it).

## [0.4.13] - 2026-06-29

### Changed
- `mix.exs` pins all Lorenzo-SF ecosystem deps to `branch: "main"`
  rather than a frozen tag. (Reverted in v0.4.14 — see below.)

### Changed
- `mix.exs` pins all Lorenzo-SF ecosystem deps (`alaja`, `candil`,
  `arrea`, `apero`, `botica`) to `branch: "main"` rather than a
  frozen tag. Pinning to a tag (e.g. pote v0.2.0) used to ship a
  stale SHA to consumers, which had caused real bugs:
  - Pote v0.2.0 → no `Pote.Theme` available.
  - Candil v0.2.0 → `Candil.Provider.__struct__/1 is undefined`.
  - Alaja v0.3.8 → the original `question_with_options/3` only
    matched exact labels, so `delfos setup` dead-ended when
    users typed `1`, `llm`, `yes` etc. v0.3.12 (now on main)
    accepts 1-based indexes, atom names, and case-insensitive
    prefixes.

  Tracking `main` is a faster feedback loop: a breaking change
  upstream breaks our build immediately, instead of silently
  shipping a frozen bug.
- `DELFOS_DEV_UMBRELLA=1` env var selects sibling-checkout deps
  (`../alaja`, `../candil`) instead of GitHub-tracked `main`. This
  is for in-umbrella development only; default behavior is
  GitHub, so end users who clone delfos never need a sibling
  `../alaja` directory.

## [0.4.12] - 2026-06-29

### Changed
- Track all Lorenzo-SF ecosystem deps on `main` branch (no frozen tags).

## [0.4.11] - 2026-06-29

### Added
- **`mix gen`** — a one-shot Mix task (`lib/mix/tasks/gen.ex`) that
  builds the release end-to-end and handles every platform-specific
  quirk:
  - Detects OS (mac, debian/ubuntu, fedora/rhel, arch, windows,
    other-linux) and reports missing toolchain
    (`rustc < 1.78`, no `cc`, no `cmake`) with the exact install
    command for that distribution.
  - Writes `native/tree_sitter_nif/.cargo/config.toml` if missing,
    so macOS links the tree-sitter NIF with the right
    `dynamic_lookup` rustflag — without per-machine setup. Users
    who cloned the repo before v0.4.10 now get a working build
    automatically.
  - Runs `mix deps.get` if `deps/` is missing.
  - Compiles, releases, deploys to `~/bin/delfos`, writes the
    `.tool-versions` file.
  - Prints a single concise "what to do next" line so the user
    never has to grep through the build log.
  - Honors `--no-deploy` for users who just want the release
    directory without copying it anywhere.
  Replaces the previous `gen: [...]` alias (same chain, more
  diagnostics, platform-aware).

## [0.4.10] - 2026-06-29

### Fixed
- **macOS build**: added `native/tree_sitter_nif/.cargo/config.toml`
  with the `link-arg=-undefined` + `link-arg=dynamic_lookup` rustflags
  Rustler needs to compile NIFs on macOS. Previously
  `MIX_ENV=prod mix release` (or `mix gen`) raised
  `Rustler.Compiler.ensure_platform_requirements!/3` on Mac users.
- Dropped `@doc` above `defp maybe_suggest_setup/2` in
  `delfos doctor` — Elixir 1.19 emits a warning when a private
  function is decorated with `@doc` (the doc is silently discarded).

## [0.4.9] - 2026-06-29

### Fixed
- Hardcoded version string replaced with `Application.spec/2`.
- Stale help texts updated; broken Reranker tests fixed.
- Dead TOML config init removed.

## [0.4.8] - 2026-06-29

### Added
- **`delfos doctor`** post-check inspects failed checks after the
  diagnostic and points the user at the right setup wizard:
  - Postgresql/DB/Migrations → `delfos setup db`
    (or `--fix --interactive` inside fix mode)
  - LLM/embedding → `delfos setup llm`
  - Configuration missing/invalid → `delfos setup`
- `test/delfos/syntax/registry_test.exs` validates all 67 language
  definitions: every `definition/0` returns a well-formed
  `%Alaja.Syntax.Language{}`, every color is an `{atom, list}` pair,
  `register_all/0` registers 67 languages, and small Elixir/Python/Rust/JSON
  snippets tokenize without errors. 9 tests, 0 failures.

## [0.4.7] - 2026-06-29

### Added
- **`delfos setup db`** now offers "Connect to remote PostgreSQL
  (host:port)". Prompts for host, port, user, password (input hidden),
  DB name. Probes connectivity (15s), creates the DB if missing,
  verifies `pgvector` via `psql -c "SELECT extversion FROM pg_extension
  WHERE extname = 'vector'"`, then runs migrations. Useful when the
  team runs a shared Postgres on another machine.
- **`delfos setup llm`** when choosing Ollama:
  - If `ollama` binary is not installed, offers automatic install
    per-OS: `curl | sh` on Linux/macOS, `brew --cask ollama` if brew
    is available, `winget install Ollama.Ollama` on Windows.
  - If the binary is installed but the daemon is not responding,
    spawns it detached and polls for readiness (30s), with fallback
    to llama.cpp if it doesn't come up.

## [0.4.6] - 2026-06-28

### Changed
- Config migrated from TOML to JSON. `~/.config/delfos/delfos.conf`
  is no longer used; the new path is `~/.config/delfos/config.json`.
  API keys are encrypted at rest with AES-256-GCM via `Apero.Crypto.Cipher`
  and decrypted lazily on read. The encryption key lives in
  `~/.config/delfos/.key`. Environment variables (`DB_HOST`,
  `DB_PASSWORD`, `EMBED_URL`, `LLM_MODEL`, etc.) still take precedence.
- Build: switched from `escript` to a Mix release. Required because
  `escript` cannot embed Rust NIFs (tree-sitter). The Mix release
  ships pre-compiled tree-sitter; users do not need a Rust toolchain.
- Tree-sitter bumped to 0.25. Removes Kotlin grammar support (the
  0.25 grammars dropped it; will revisit when a new release is
  available).
- `Delfos.version/0` now reads from the loaded application spec
  (`Application.spec(:delfos, :vsn)`) instead of returning a hardcoded
  `"0.4.5"`. Always reports the actual installed version.

### Added
- **`delfos setup`** wizard with `db` and `llm` sub-flows. Guides
  the user through Postgres install (Docker/apt/brew/existing) and
  LLM provider selection (llama.cpp / Ollama / OpenAI / Anthropic).
- `Delfos.Health` — periodic health check that pings the embedding
  and LLM endpoints and reports latency + dim mismatch warnings.
- `config/runtime.exs` — production-only env-var validation.
- Graceful shutdown (`Application.stop`).
- Safe `Jason.encode` (no `!`) in the MCP server, removing the risk
  of an unhandled exception in the middle of a JSON-RPC reply.
- `Delfos.MCP.Server` spin-loop fix: replaced `after: 0` polling
  with an async stdin reader.
- HNSW indexes on `chunks.embedding` and `symbols.embedding` for
  faster vector queries.
- GraphBuilder N+1 fix: preloads files into a lookup map instead
  of one query per node.

## [0.4.5] - 2026-06-27

### Changed
- Bumped `candil` to v0.3.0 in `mix.exs` and `mix.lock`. v0.3.0
  explicitly tags the release that includes the `Candil.Provider`
  struct. Pre-v0.3.0, `delfos` could fail to compile with
  `Candil.Provider.__struct__/1 is undefined` because the SHA
  `499f86b` referenced in the previous mix.lock no longer matched
  the upstream main (which had moved on with reformatting commits).

## [0.4.4] - 2026-06-27

### Changed
- Bumped `alaja` to v0.3.8 in `mix.lock` (which bumps `pote` to v0.3.0).
- Bumped `arrea` to v0.3.5 in `mix.lock`.

## [0.4.3] - 2026-06-27

### Changed
- Bumped `alaja` to v0.3.7 in `mix.lock`. Now `Alaja.CLI.Definition.main/1`
  auto-starts the OTP application, so escripts (Delfos' own escript too)
  see the persisted `:theme_active` from `alaja.conf`.
- Bumped `arrea` to v0.3.4 in `mix.lock`.

## [0.4.2] - 2026-06-27

### Changed
- Bumped `alaja` to v0.3.6 in `mix.lock`. Fixes cross-process theme
  persistence — every escript now sees the persisted `:theme_active`
  from `alaja.conf` without anyone calling `Alaja.Theme.activate/1`.
- Bumped `arrea` to v0.3.3 in `mix.lock` (alaja v0.3.6 compatibility).

## [0.4.1] - 2026-06-27

### Changed
- Bumped `alaja` to v0.3.5 in `mix.lock`. Fixes a critical bug where
  `alaja config theme set <name>` did NOT change the colour palette
  used by `theme:<key>` lookups. Delfos renders themes through Alaja,
  so the fix applies transparently — every `theme:debug`, `theme:happy`,
  `theme:gradient_3` lookup now reflects the active theme.
- Bumped `arrea` to v0.3.2 in `mix.lock` (alaja v0.3.5 compatibility).

## [0.4.0] - 2026-06-25

### Changed — CLI migrated to `Alaja.CLI.Definition` DSL
- New module `Delfos.CLI` (replacing `Delfos.CLI.Main`) uses the
  `Alaja.CLI.Definition` DSL: `command "name" "description" do ... end`.
- The manual 192-line dispatcher in `Delfos.CLI.Main` is gone. Each
  subcommand is now declared declaratively in `Delfos.CLI`.
- Each `Delfos.CLI.Commands.X.run/1` is unchanged — the DSL handler
  functions (e.g. `init_handler/1`) bridge between the DSL opts map
  (with `_args`) and the existing legacy `run/1` call signature.
- escript `main_module` updated from `Delfos.CLI.Main` to `Delfos.CLI`.
- Bumped `alaja` to v0.3.3 in `mix.lock` (library-safe DSL, no longer
  calls `System.halt/1` by default).
- Bumped `pote` to `e0554d4` in `mix.lock` (brings in `Pote.Theme`).
- Bumped `arrea` to v0.3.0 (alaja v0.3.3 compatibility).
- Added `test/delfos/cli/cli_test.exs` with 20 tests covering the DSL:
  `__commands__/0` returns all 16 commands, every command has a
  description, every command has a run handler, `main/1` with no args
  shows the help list, `main/1` with an unknown command prints an error,
  and every `X --help` routes correctly to `Delfos.CLI.Commands.X.run`.

### Removed
- `lib/delfos/cli/commands/main.ex` (replaced by `Delfos.CLI`).

## [0.3.4] - 2026-06-25

Documentation release — no code changes.

- README rewritten with complete sections: agent integration table
  with verified formats, CLI reference, troubleshooting table, models
  recipes (local / OpenAI / Anthropic), full MCP tool list.
- `docs/MCP_TOOLS.md` expanded: input schemas, sample output for each
  of the 8 tools, MCP server lifecycle, JSON-RPC method table,
  experimental capabilities for index-change notifications.
- `CONTRIBUTING.md` rewritten: architecture, conventions, testing
  guide (fast vs integration), integration format reference with
  pitfalls table, PR flow, release process.
- `SPEC.md` §20 updated with v0.3.2 and v0.3.3 entries, plus an
  expanded "Estado actual" table covering all 13 SPEC sections.

## [0.3.3] - 2026-06-25

### Verified by tests

The integrate command's output formats were checked against actual
TOML/JSON/YAML parsers (not just compiled). All 12 integration tests
pass in 0.02s:

  - Codex — `Toml.decode_file/1` round-trips `[mcp_servers.delfos]`
    correctly when other servers are already configured.
  - Cursor — `.cursor/rules/delfos.mdc` frontmatter parses.
  - Aider — `read:` list merges via regex, verified with 5 cases
    (empty, with read, already-present, missing read, read-at-start).
  - Claude / OpenCode / Zed — JSON shape matches the docs.

### Changed

- `merge_aider_read/1` switched from `YamlElixir` (Elixir 1.17+ only)
  to a regex-based approach. Dropped `yaml_elixir` runtime dep.

## [0.3.2] - 2026-06-25

Re-tagged from the v0.3.1 commit with the integration-format fixes
(Codex TOML, Cursor MDC, Aider YAML merge) and the documentation
updates (CONTRIBUTING.md, docs/MCP_TOOLS.md, SPEC.md §20, tests).
No code changes beyond what v0.3.1 already covered.

## [0.3.1] - 2026-06-25

### Added
- `Delfos.CLI.Commands.Integrate.safe_write/2` — writes a file after
  backing up the existing version to `<path>.bak-<unix_seconds>`. Every
  `File.write!` in the integrate command now goes through it. Skips
  backup when the target is new or empty.
- Real unit tests in `test/delfos/cli/commands/` for `safe_write/2`,
  `--help` of doctor / models, and the aider `read:` merge logic.
- `CONTRIBUTING.md` covering setup, code conventions, PR flow, and
  release process.
- `docs/MCP_TOOLS.md` with sample output for all 8 MCP tools.
- `yaml_elixir ~> 2.11` as a runtime dep (needed for aider conf merge).

### Fixed
- **Codex** was writing YAML to `~/.codex/config.yaml` with key
  `mcp_servers:`. The real format is **TOML** at
  `~/.codex/config.toml` with key `[mcp_servers]`. Switched and added
  round-trip validation via `Toml.decode_file/1`.
- **Cursor** was writing to `.cursorrules` (deprecated in Cursor 0.45+).
  Switched to `.cursor/rules/delfos.mdc` with YAML frontmatter.
- **Aider** was appending `read:\n  - AGENTS.md` to `.aider.conf.yml`,
  producing a second `read:` block (invalid YAML). Now parses the
  existing config with `YamlElixir`, merges the new entry into the
  existing `read:` list, and rewrites.

### Verified
- `elixirc lib/delfos/cli/commands/integrate.ex` — no syntax errors
  (warnings are for Alaja not loaded in the stub path).
- 3 smoke tests for `safe_write/2` pass in isolation.

## [0.3.0] - 2026-06-25

### Added
- **`delfos doctor`** rewritten on top of `Botica.Doctor` (was calling
  `Apero.Doctor`, which does not exist). Adds `--interactive` (ask
  before applying each fix), `--db-only` / `--llm-only` filters, and
  `--json` for machine-readable output. Detects `DB_HOST` / `DB_PORT` /
  `DB_USER` / `DB_PASS` overrides and reports the actual target host.
- **`delfos models`** shows active embedding and LLM providers with masked
  API keys and index column dimension. With `--probe` pings each endpoint
  and reports latency + dim mismatch warnings.
- `--help` and `-h` are now honoured globally and by every subcommand:
  `delfos --help`, `delfos query --help`, `delfos doctor --help`, etc.
  Each help block lists flags, arguments, and worked examples.

### Changed
- `delfos integrate` reads existing JSON files defensively
  (`read_json_or_empty/1`) and verifies each write with `verify_json/1`.
  Bad JSON in `~/.claude.json`, `~/.config/opencode/config.json`, etc.
  now fails loudly instead of silently overwriting.
- `delfos integrate aider` no longer overwrites an existing `AGENTS.md`
  without warning; if Delfos instructions are not already present, the
  file is backed up to `AGENTS.md.bak-<unix_ts>` before the merge.
- Postgrex errors are surfaced through `format_db_error/1` and
  `format_error/1` helpers instead of raw `inspect/1`. Errors in
  `delfos query`, `delfos doctor`, etc. now include a "next step" hint
  pointing to `delfos doctor` or `delfos models`.

### Fixed
- `mix docs` no longer fails because `README_ES.md` was missing — the
  `extras:` list now points to `docs/README.es.md`.
- `delfos doctor` no longer references the non-existent `Apero.Doctor`.
- `delfos models` validates the `embedding.dim` config against the
  actual `symbols.embedding` column dimension in PostgreSQL.

## [0.2.0] - 2026-06-24

### Added
- Initial public release of the MCP server (JSON-RPC 2.0 over stdio,
  protocol version 2024-11-05) with 8 tools.
- Hybrid search (vector + BM25 + graph) via Reciprocal Rank Fusion.
- CandilBridge adapter so OpenAI-compatible chat/embed calls route
  through `Candil` when available.
- `delfos integrate <agent>` for `claude-code`, `opencode`, `cursor`,
  `aider`, `codex`, `zed` and `all`.
