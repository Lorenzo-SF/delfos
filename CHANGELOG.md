# Changelog

All notable changes to Delfos will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

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
