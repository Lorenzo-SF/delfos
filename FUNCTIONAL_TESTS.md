# Functional testing — CLI and MCP coverage map

> **Date**: 2026-08-13
> **Status**: Mapping complete. Test files NOT yet written — this is
> a plan for the next session to execute.

## Overview

This file maps every user-facing entry point in delfos to functional
tests we should write. The goal is to catch regressions in:

- The CLI surface (16 commands) — invocation, flags, output,
  exit codes, file side effects.
- The MCP server surface (8 tools) — JSON-RPC over stdio/HTTP,
  tool arguments, response shape.

Tests live under `test/functional/`, tagged `@tag :functional`,
run via the new alias `mix test.functional`.

## CLI commands (16)

Source: `lib/delfos/cli.ex` and `lib/delfos/cli/commands/*.ex`

| # | Command | Module | Functional test | Scenarios |
|---|---------|--------|-----------------|-----------|
| 1 | `delfos init <path>` | `Delfos.CLI.Commands.Init` | `test/functional/cli_init_test.exs` | - happy path: valid project dir<br>- error: path doesn't exist<br>- error: path is a file not a dir<br>- error: missing LLM endpoint<br>- happy path: explicit `--project-id` |
| 2 | `delfos scan` | `Delfos.CLI.Commands.Scan` | `test/functional/cli_scan_test.exs` | - happy: full scan of medium fixture<br>- `--full` vs incremental<br>- workers override (`--workers 8`)<br>- error: no active project |
| 3 | `delfos query <text>` | `Delfos.CLI.Commands.Query` | `test/functional/cli_query_test.exs` | - happy: returns matches<br>- empty text → help<br>- no matches → empty list<br>- level filter (`--level chunk`)<br>- kind filter (`--kind function`) |
| 4 | `delfos audit` | `Delfos.CLI.Commands.Audit` | `test/functional/cli_audit_test.exs` | - happy: project with debt<br>- `--file` filter<br>- JSON output (`--json`) |
| 5 | `delfos summarize` | `Delfos.CLI.Commands.Summarize` | `test/functional/cli_summarize_test.exs` | - happy: generates summaries<br>- `--level` overrides<br>- `--force` re-summarize |
| 6 | `delfos explain <name>` | `Delfos.CLI.Commands.Explain` | `test/functional/cli_explain_test.exs` | - happy: explains a symbol<br>- error: symbol not found<br>- `--fresh` flag |
| 7 | `delfos graph <sub> <name>` | `Delfos.CLI.Commands.Graph` | `test/functional/cli_graph_test.exs` | - `callers` for a function<br>- `callees` for a function<br>- `impact` for a function<br>- `cycles` (with cycle fixture)<br>- `--depth` override |
| 8 | `delfos agents` | `Delfos.CLI.Commands.Agents` | `test/functional/cli_agents_test.exs` | - happy: generates AGENTS.md<br>- `--output` to custom dir<br>- `--symbol` focused context |
| 9 | `delfos context` (deprecated) | `Delfos.CLI.Commands.Context` | `test/functional/cli_context_test.exs` | - deprecation warning printed<br>- forwards to agents |
| 10 | `delfos config <action>` | `Delfos.CLI.Commands.Config` | `test/functional/cli_config_test.exs` | - `config show`<br>- `config path`<br>- `config set llm model foo`<br>- `config get llm model`<br>- `config preset openai`<br>- `config preset bogus` → error |
| 11 | `delfos integrate <agent>` | `Delfos.CLI.Commands.Integrate` | `test/functional/cli_integrate_test.exs` | - `integrate claude-code`<br>- `integrate opencode`<br>- `integrate --all` (default) |
| 12 | `delfos doctor` | `Delfos.CLI.Commands.Doctor` | `test/functional/cli_doctor_test.exs` | - happy: all checks pass<br>- `--preflight` exit code 0/1/2<br>- `--fix` actually fixes |
| 13 | `delfos status` | `Delfos.CLI.Commands.Status` | `test/functional/cli_status_test.exs` | - happy: shows indexed projects<br>- empty: prints guidance |
| 14 | `delfos watch` (deprecated) | `Delfos.CLI` | covered in `cli_test.exs` | - prints deprecation, forwards to mcp |
| 15 | `delfos mcp` | `Delfos.CLI` | `test/functional/cli_mcp_test.exs` | - stdio mode boots without error<br>- `--transport http` starts Bandit<br>- exit code 0 on SIGTERM |
| 16 | `delfos version` | `Delfos.CLI` | covered in `cli_test.exs` | - prints version |

## Global CLI flags

- `--help`, `-h` → already covered in `cli_test.exs`
- `--version`, `-v` → already covered in `cli_test.exs`
- Global flag interaction: `delfos --version` should NOT trigger LLM
  guard (covered in `cli_test.exs:111`)

## MCP tools (8)

Source: `lib/delfos/mcp/tools.ex` and `lib/delfos/mcp/server.ex`

MCP tests use JSON-RPC 2.0 over stdio. Setup:
- `Delfos.MCP.Server.start_link/0` with mock stdin/stdout
- Send `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}`
- Send `{"jsonrpc":"2.0","method":"tools/call","params":{"name":"...","arguments":{...}}}`
- Assert on response shape

| # | Tool | Functional test | Scenarios |
|---|------|-----------------|-----------|
| 1 | `delfos_search` | `test/functional/mcp_search_test.exs` | - happy: returns matches<br>- empty query → error<br>- no project active → error<br>- limit / kind filters |
| 2 | `delfos_symbol` | `test/functional/mcp_symbol_test.exs` | - happy: returns symbol<br>- symbol not found → error<br>- partial name match |
| 3 | `delfos_context` | `test/functional/mcp_context_test.exs` | - happy: returns task context<br>- task required (NimbleOptions)<br>- invalid args → error |
| 4 | `delfos_callers` | `test/functional/mcp_callers_test.exs` | - happy: returns callers list<br>- symbol not found → error |
| 5 | `delfos_callees` | `test/functional/mcp_callees_test.exs` | - happy: returns callees list<br>- symbol not found → error |
| 6 | `delfos_impact` | `test/functional/mcp_impact_test.exs` | - happy: returns impact list<br>- depth override |
| 7 | `delfos_audit` | `test/functional/mcp_audit_test.exs` | - happy: returns audit<br>- `file` filter |
| 8 | `delfos_files` | `test/functional/mcp_files_test.exs` | - happy: returns files<br>- filter by language<br>- pagination (limit/offset) |

## HTTP MCP transport (FE-7)

- `test/functional/mcp_http_test.exs`
- Boots Bandit on random port
- Posts JSON-RPC over HTTP
- Asserts response headers + body

## Test infrastructure

- All tests use the `bench/fixtures/` projects (small/medium/large)
  as input. They are generated lazily on first run.
- All tests start a clean `Delfos.Repo` Sandbox via the existing
  `Delfos.TestHelper`.
- All tests use a `tmp_dir` setup that auto-cleans on exit.

## Implementation order (priority)

1. **CLI doctor** (easiest, most useful — catches config regressions)
2. **CLI version/help/global flags** (already covered, double-check)
3. **CLI status** (no DB writes, easy)
4. **CLI config** (covers a wide surface)
5. **CLI init/scan/query/audit** (covers the core flow)
6. **CLI graph/agents/context** (specialized flows)
7. **MCP tools** (requires JSON-RPC test harness)
8. **HTTP MCP transport** (requires Bandit + Plug.Conn test harness)

Estimated total: 6-8 hours of focused test writing.
