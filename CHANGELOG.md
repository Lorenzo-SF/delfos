# Changelog

All notable changes to Delfos will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

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

## [0.4.3] - 2026-06-27

### Changed
- Bumped `alaja` to v0.3.7 in `mix.lock`. Now `Alaja.CLI.Definition.main/1`
  auto-starts the OTP application, so escripts (Delfos' own escript too)
  see the persisted `:theme_active` from `alaja.conf`.
- Bumped `arrea` to v0.3.4 in `mix.lock`.

## [0.4.2] - 2026-06-27

## [0.4.2] - 2026-06-27

### Changed
- Bumped `alaja` to v0.3.6 in `mix.lock`. Fixes cross-process theme
  persistence — every escript now sees the persisted `:theme_active`
  from `alaja.conf` without anyone calling `Alaja.Theme.activate/1`.
- Bumped `arrea` to v0.3.3 in `mix.lock` (alaja v0.3.6 compatibility).

## [0.4.1] - 2026-06-27

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
