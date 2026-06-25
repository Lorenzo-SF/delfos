# Contributing to Delfos

Thanks for your interest in contributing. This document covers how to
set up a development environment, the conventions we follow, and how
to submit changes.

## Setup

Delfos requires:

- Elixir 1.19.5 / OTP 28 (see `.tool-versions`)
- PostgreSQL 14+ with the `vector` extension
- Two `llama-server` processes for embedding (port 9998) and LLM (port 8080),
  unless you're using OpenAI / Anthropic presets

```bash
git clone https://github.com/Lorenzo-SF/delfos
cd delfos
mix deps.get
mix compile
```

Configure your local models:

```bash
delfos config init           # creates ~/.config/delfos/delfos.conf
delfos config preset local   # default llama.cpp URLs + models
# Or:
delfos config preset openai
delfos config set llm api_key sk-...
```

Create the database:

```bash
mix ecto.create
mix ecto.migrate
```

Verify everything is wired up:

```bash
delfos doctor
delfos models --probe
```

## Architecture

Delfos is part of Lorenzo-SF's Elixir OSS ecosystem. It depends on:

- **Alaja** — terminal rendering framework (icons, colours)
- **Arrea** — async process orchestrator
- **Apero** — OS detection, docker helpers, etc.
- **Botica** — `Botica.Doctor` powers `delfos doctor`
- **Candil** — multi-provider LLM client (optional, dev/test only)
- **Pote** — colour/theme utilities

See `SPEC.md` for the full architectural reference.

## Code conventions

1. **Output through Alaja.** CLI commands use `Alaja.print_info/1`,
   `Alaja.print_warning/1`, `Alaja.print_error/1`, `Alaja.print_success/1`,
   `Alaja.print_raw/1`. Never use `IO.puts/1` in CLI code.

2. **Errors with context.** Postgrex errors, Req errors, etc. should go
   through a small `format_*/1` helper that strips inspect/1 noise and
   adds a "next step" hint pointing to `delfos doctor` or
   `delfos models`.

3. **Help blocks.** Every CLI subcommand exposes a `@help` string
   printed by `run(["--help"])` and `run(["-h"])`. List flags, args,
   and worked examples.

4. **Safe file writes.** Anything that touches user-owned config
   (claude.json, aider conf, codex toml, etc.) goes through
   `Delfos.CLI.Commands.Integrate.safe_write/2`, which creates a
   timestamped backup before overwriting.

5. **Hex package pinning.** Cross-repo dependencies (Alaja, Arrea,
   Botica, Candil, Pote) are pinned by **tag**, not raw SHA. Format:
   `{:botica, github: "Lorenzo-SF/botica", tag: "v0.3.0"}`. Use
   `python3` with explicit string replacement for SHA bumps — `sed`
   corrupts hex checksums.

## Pull requests

- Branch from `main`. Use `fix/...`, `feat/...`, `chore/...` prefixes.
- Keep commits small and message-driven: `fix(delfos): ...`,
   `feat(integrate): ...`. See any recent merge commit for examples.
- Force-push to your branch is fine; **never** force-push to `main`.
- Before opening a PR, run locally:

  ```bash
  mix format --check-formatted
  mix credo --strict
  mix test
  mix dialyzer
  ```

- Open the PR against `main`. Tag a maintainer for review.

## Release process

1. Cut a release branch: `git checkout -b release/v0.4.0`
2. Bump `@version` in both `mix.exs` and `lib/delfos.ex` (they drift
   — keep them in sync manually).
3. Update `CHANGELOG.md` with a new section. The unreleased block at
   the top accumulates changes since the last release.
4. `git tag -a v0.X.Y -m "Release v0.X.Y — ..."` and push with
   `git push origin v0.X.Y`.
5. The CI pipeline builds the escript via `mix batamanta` and
   publishes binaries to the GitHub release.

## Reporting bugs

Open an issue at <https://github.com/Lorenzo-SF/delfos/issues> with:

- `delfos doctor --json` output (it strips secrets but tells us what's broken)
- `delfos models --probe` output
- The exact command you ran
- Expected vs actual behaviour
- For embedding/LLM issues: include `~/.config/delfos/delfos.conf`
  with API keys masked (replace middle with `...`).

## License

By contributing, you agree that your contributions will be licensed
under the MIT License — see [LICENSE.md](LICENSE.md).
