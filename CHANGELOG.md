# Changelog

All notable changes to Delfos will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

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
