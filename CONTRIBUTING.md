# Contributing to Delfos

Thanks for your interest in contributing. This document covers how to
set up a development environment, the conventions we follow, how to
verify your changes, and how to submit them.

## Setup

Delfos requires:

- **Elixir 1.19.5 / OTP 28** (see `.tool-versions`)
- **PostgreSQL 14+** with the `vector` extension
- Two `llama-server` processes (embedding port 9998, LLM port 8080),
  unless you're using OpenAI / Anthropic presets

```bash
git clone https://github.com/Lorenzo-SF/delfos
cd delfos
mix deps.get
mix compile
```

For local Elixir versions older than 1.19, the codebase will still
compile but `mix format` rules may differ slightly.

### Configure models

```bash
delfos config init           # creates ~/.config/delfos/delfos.conf
delfos config preset local   # default llama.cpp URLs + models
# Or:
delfos config preset openai
delfos config set llm api_key sk-...
```

### Create the database

```bash
mix ecto.create
mix ecto.migrate
```

### Verify everything is wired up

```bash
delfos doctor
delfos models --probe
```

## Architecture

Delfos is part of Lorenzo-SF's Elixir OSS ecosystem. Runtime deps:

- **Alaja** — terminal rendering (icons, colours)
- **Arrea** — async process orchestrator
- **Botica** — `Botica.Doctor` powers `delfos doctor`
- **Candil** — multi-provider LLM client (dev/test only)
- **Pote** — colour/theme utilities
- **Apero** — was runtime dep until 2026-07; crypto (AES-256-GCM) is
  now inlined on Erlang `:crypto` in `Delfos.Config.Manager`. Repo
  kept for other consumers.
- **YamlElixir** is **not** a dep — `merge_aider_read/1` uses a
  regex-based parser to avoid the Elixir 1.17+ requirement.

See `SPEC.md` for the full architectural reference.

## Code conventions

1. **Output through Alaja.** CLI commands use `Alaja.print_info/1`,
   `Alaja.print_warning/1`, `Alaja.print_error/1`, `Alaja.print_success/1`,
   `Alaja.print_raw/1`. Never use `IO.puts/1` in CLI code.

2. **Errors with context.** Postgrex errors, Req errors, etc. should
   go through a small `format_*/1` helper that strips inspect/1 noise
   and adds a "next step" hint pointing to `delfos doctor` or
   `delfos models`.

3. **Help blocks.** Every CLI subcommand exposes a `@help` string
   printed by `run(["--help"])` and `run(["-h"])`. List flags, args,
   and worked examples.

4. **Safe file writes.** Anything that touches user-owned config
   (claude.json, aider conf, codex toml, zed settings, etc.) goes
   through `Delfos.CLI.Commands.Integrate.safe_write/2`, which
   creates a timestamped backup before overwriting.

5. **Verified formats.** When adding or modifying an integration
   (Claude Code, OpenCode, Cursor, Aider, Codex, Zed), update
   `test/delfos/cli/commands/integrate_formats_test.exs` to verify
   the output with a real parser (Toml, Jason, regex for YAML).
   The test suite has 12 passing tests in 0.02s.

6. **Hex package pinning.** Cross-repo dependencies (Alaja, Arrea,
   Botica, Candil, Pote) are pinned by **tag**, not raw SHA. Format:
   `{:botica, github: "Lorenzo-SF/botica", tag: "v0.3.3"}`. Use
   `python3` with explicit string replacement for SHA bumps — `sed`
   corrupts hex checksums.

## Testing

### The fast unit tests (no DB, no runtime deps)

```bash
mix test test/delfos/cli/commands/integrate_test.exs
mix test test/delfos/cli/commands/integrate_formats_test.exs
```

These tests verify:

- `safe_write/2` backup behaviour (new/empty/existing files,
  nested configs)
- Codex TOML format round-trips with pre-existing servers
- Cursor MDC frontmatter parsing
- Aider YAML `read:` list merge via regex (5 scenarios)
- Claude / OpenCode / Zed JSON shape matches agent docs

These do **not** require Alaja or a database. They run in <0.1s.

### Integration tests (require full deps + DB)

Marked with `@tag :integration`. Run with:

```bash
MIX_ENV=integration mix test --include integration
```

These exercise `--help` output (which depends on Alaja.print_raw/1)
and database-backed flows in `delfos doctor`, `delfos models --probe`,
etc.

### Verifying your own change

Before opening a PR, run:

```bash
mix format --check-formatted
mix credo --strict
mix test test/delfos/cli/commands/      # fast unit tests
MIX_ENV=integration mix test --include integration  # full suite
mix dialyzer
```

## Integration format reference

When writing or modifying integration helpers in
`lib/delfos/cli/commands/integrate.ex`, refer to the agent's actual
documentation:

| Agent | Doc |
|-------|-----|
| Claude Code | <https://docs.claude.com/en/docs/claude-code/mcp> |
| OpenCode | <https://opencode.ai/docs/> |
| Cursor | <https://docs.cursor.com/context/model-context-protocol> |
| Aider | <https://aider.chat/docs/config/aider_conf.html> |
| Codex | <https://github.com/openai/codex/blob/main/docs/config.md> |
| Zed | <https://zed.dev/docs/extensions/context-servers> |

### Format pitfalls (verified by tests in v0.3.3)

- **Codex reads TOML, not YAML** — `[mcp_servers.delfos]` not
  `mcpServers:`. Writing YAML is silently ignored.
- **Cursor 0.45+ ignores `.cursorrules`** — write
  `.cursor/rules/delfos.mdc` with YAML frontmatter instead.
- **Aider `read:` is a YAML list** — appending a second `read:`
  block produces invalid YAML. Merge into the existing list.
- **Claude Code uses `mcpServers.{name}.{type,command,args}`** —
  not `mcpServers.{name}.config.command`.

## Pull requests

- Branch from `main`. Use `fix/...`, `feat/...`, `chore/...` prefixes.
- Keep commits small and message-driven: `fix(delfos): ...`,
  `feat(integrate): ...`. See recent merge commits for examples.
- Force-push to your branch is fine; **never** force-push to `main`.
- Before opening a PR, run the verification suite (above).
- Open the PR against `main`. Tag a maintainer for review.

## Release process

1. Cut a release branch: `git checkout -b release/v0.4.0`
2. Bump `@version` in **both** `mix.exs` AND `lib/delfos.ex` (they
   drift — keep them in sync manually).
3. Add a section to `CHANGELOG.md` under `## [Unreleased]`. Move the
   `## [Unreleased]` marker down to the bottom of the file when
   cutting the release.
4. `git tag -a v0.X.Y -m "Release v0.X.Y — ..."` and push with
   `git push origin v0.X.Y`.
5. The CI pipeline builds the escript via `mix batamanta` and
   publishes binaries to the GitHub release.

## Reporting bugs

Open an issue at <https://github.com/Lorenzo-SF/delfos/issues> with:

- `delfos doctor --json` output (strips secrets, tells us what's broken)
- `delfos models --probe` output
- The exact command you ran
- Expected vs actual behaviour
- For embedding/LLM issues: include `~/.config/delfos/delfos.conf`
  with API keys masked (replace middle with `...`).

## License

By contributing, you agree that your contributions will be licensed
under the MIT License — see [LICENSE.md](LICENSE.md).
