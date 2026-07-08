# NIF tree-sitter: Fix para extracción de `defmodule` (módulos Elixir)

> **Status**: ready to be implemented
> **Audience**: another agent in a fresh session
> **Goal**: fix the Rust NIF so it extracts Elixir `defmodule` nodes (not only
> functions/classes/structs), so the `symbols.kind` enum gets `module`
> entries and the indexer represents Elixir projects faithfully.
> **Relates to**: [TEST_PLAN.md](./TEST_PLAN.md) — section 4.3 (init on
> real project) expects 367 symbols (170 defmodules + 197 functions).
> Current state: 371 symbols, ALL `kind = function`. Zero modules.

---

## 1. Context

### 1.1 What is Delfos?

Delfos is a **code intelligence CLI** that indexes source code repositories
into PostgreSQL + pgvector for semantic + structural search via MCP (Model
Context Protocol). The architecture:

- **Elixir umbrella** at `~/cacafuti/delfos/` (Elixir 1.19.5, OTP 28, pgvector 0.8.4).
- **Rust NIF** (`native/tree_sitter_nif/`) does the actual parsing via
  tree-sitter grammars. Compiled beam links to it via Rustler.
- **CLI binary** at `~/bin/delfos` (or the project root `delfos`); built via
  `mix batamanta` (custom Mix task — see "How to build" below).
- **DB schema**: projects, files, symbols, chunks, summaries,
  relationships, file_metrics. Symbols have a `kind` field
  (`function | module | class | struct | macro | trait | interface`).
- **MCP server** at `delfos mcp` exposes 8 tools (delfos_search,
  delfos_symbol, delfos_context, delfos_callers, delfos_callees,
  delfos_impact, delfos_audit, delfos_files) consumed by AI agents
  (opencode, claude-code, cursor, codex, zed).

### 1.2 The bug

When a user runs `delfos init ~/cacafuti/delfos` (the delfos project
itself), the result is **371 symbols, all with `kind = function`**.
Source code contains **137 `defmodule` declarations in `lib/` plus 33
in `test/` = 170 modules**. **Zero are recorded as `kind = module`**.

The `Symbol.changeset` cast list in `lib/delfos/schema/symbol.ex` allows
`module` as a valid `kind`. The query in
`lib/delfos/indexer/graph_builder.ex:84` filters by
`["function", "module", "class", "macro", "struct", "trait", "interface"]`
— but the NIF never returns `module`, so this filter doesn't matter.

The downstream impact:
- `delfos audit` → `QUALITY INDEX: Symbols with embedding: X/Y` is misleading
  because it doesn't count modules.
- `delfos graph` call graphs (callers/callees) miss the file-level
  structure that would emerge if modules were first-class.
- `delfos search` with `kind=module` returns nothing.
- `delfos impact` BFS analysis is incomplete.

### 1.3 What is known to work

- Function extraction: tree-sitter-elixir extracts `def`, `defp`,
  `defmacro` etc. → stored as `kind = function`.
- Class / struct extraction works for Rust (verified: 1 struct,
  6 functions in `native/tree_sitter_nif/src/lib.rs`).
- `mix xref graph` produces 277 file-level edges in
  `xref_graph.dot` and now they're persisted to the
  `relationships` table after the 20260708000002 migration.
- `delfos_search`, `delfos_symbol`, `delfos_audit` all return
  proper results through opencode MCP integration.

### 1.4 What is broken

Only the `defmodule` extraction in the Rust NIF. The fix is
localised to `native/tree_sitter_nif/src/lib.rs` (and the
`Cargo.toml` if a new grammar dependency is needed; tree-sitter-elixir
should already be there).

---

## 2. Reproduction

### 2.1 Sanity check the bug exists

```bash
cd ~/cacafuti/delfos
export PATH=/usr/lib/ollama:$PATH  # required for llama-server

# Wipe and re-init the project
mix run -e '
Application.ensure_all_started(:delfos)
alias Delfos.{Repo, Schema}
import Ecto.Query
Repo.delete_all(Schema.Relationship)
Repo.delete_all(Schema.FileMetrics)
Repo.delete_all(Schema.Chunk)
Repo.delete_all(Schema.Summary)
Repo.delete_all(Schema.Symbol)
Repo.delete_all(Schema.File)
Repo.delete_all(Schema.Project)
IO.puts "wiped"
'

~/bin/delfos init ~/cacafuti/delfos 2>&1 | tail -3

# Count by kind
mix run -e '
Application.ensure_all_started(:delfos)
{:ok, %{rows: kinds}} = Ecto.Adapters.SQL.query(Delfos.Repo, "SELECT kind, COUNT(*) FROM symbols GROUP BY 1")
IO.inspect kinds, label: "kinds"
'
# Expected (bug): [{function, 371}]
# Expected (fix): [{function, 197}, {module, 170}, ...]
```

### 2.2 Source-side evidence

```bash
grep -rE "^defmodule " /home/merendandum/cacafuti/delfos/lib --include="*.ex" | wc -l
# 137
grep -rE "^defmodule " /home/merendandum/cacafuti/delfos/test --include="*.exs" | wc -l
# 33
```

`test/delfos/parser/symbol_extraction_test.exs` (if it exists in
the delfos source) may have a test asserting that `defmodule`
produces `kind: "module"`. Check first; if it does, the test is
failing today.

---

## 3. Implementation guide

### 3.1 Where to look

```
~/cacafuti/delfos/
├── native/
│   └── tree_sitter_nif/
│       ├── Cargo.toml              # tree-sitter-elixir dep
│       ├── src/
│       │   ├── lib.rs              # main NIF entry point
│       │   └── extractors/         # language-specific extractors
│       │       └── elixir.rs       # ★ this is where the fix goes
│       └── test/                   # Rust integration tests
└── lib/delfos/parsers/treesitter/
    └── tree_sitter.ex             # Elixir-side wrapper (no changes needed)
```

The `Elixir side` wrapper at `lib/delfos/parsers/treesitter/tree_sitter.ex`
handles symbol normalization (the `normalize_symbol/2` function maps
the raw NIF output to the delfos schema). If the NIF returns
`kind: "module"` for `defmodule`, the wrapper should pass it through
unchanged (no special mapping needed). Verify the wrapper's
`normalize_symbol/2` doesn't accidentally rewrite "module" to something
else.

### 3.2 How tree-sitter works for Elixir

tree-sitter-elixir parses Elixir code into a syntax tree with nodes
like:
- `call` — function calls, including `defmodule`
- `call_identifier` — the function name (e.g., `MyMod`)
- `binary_operator` — operators
- `do_block` — the body of a `do ... end`
- etc.

To detect a `defmodule`, the extractor needs to look for:

```rust
(call
  function: (identifier) @fn_name    ;; the keyword "defmodule"
  arguments: (arguments
    (alias) @module_name              ;; the module name
    ...
    (do_block) @body))
```

The current extractor likely looks only for `def`/`defp` patterns
and ignores `defmodule`. The fix is to add a query/branch that
matches `defmodule` and emits a symbol with `kind: "module"`,
`name: <module_name>`, `qualified_name: <module_name>`,
`line_start: <def_line>`, `line_end: <do_end_line>`,
`content: <source_slice>`.

### 3.3 Test before fixing

Add or run a test that demonstrates the bug:

```bash
cd ~/cacafuti/delfos
# If a test exists, run it
mix test test/delfos/parser/symbol_extraction_test.exs 2>&1 | tail -20
```

If the test asserts that `defmodule MyMod do ... end` produces a
symbol with `kind: "module"`, it will fail today. If no such test
exists, add one to the test file (do not commit if it fails — that's
the test that proves the bug).

### 3.4 The fix in Rust

Likely changes in `native/tree_sitter_nif/src/extractors/elixir.rs`:

```rust
// Pseudocode — actual API depends on the existing extractor style.
// Look for the existing function/def extractor and add a parallel
// defmodule extractor that uses the same parse_symbols pipeline.

pub fn extract_elixir_symbols(source: &str) -> Vec<ElixirSymbol> {
    let mut parser = tree_sitter::Parser::new();
    parser.set_language(tree_sitter_elixir::language()).unwrap();
    let tree = parser.parse(source, None).unwrap();
    let root = tree.root_node();

    let mut symbols = Vec::new();
    walk(root, source, &mut symbols);
    symbols
}

fn walk(node: Node, source: &str, out: &mut Vec<ElixirSymbol>) {
    // Existing: catch def / defp / defmacro
    // New: catch defmodule
    if node.kind() == "call" {
        if let Some(fn_name) = node.child_by_field_name("function") {
            let fn_text = fn_name.utf8_text(source.as_bytes()).unwrap_or("");
            match fn_text {
                "defmodule" => {
                    // Extract module name from the first arg
                    if let Some(args) = node.child_by_field_name("arguments") {
                        // The module name is in the first child of arguments
                        // (often an alias node)
                        let module_name = extract_module_name(args, source);
                        out.push(make_module_symbol(module_name, node, source));
                    }
                }
                "def" | "defp" | "defmacro" => {
                    // existing function extraction
                }
                _ => {}
            }
        }
    }
    // recurse
    for child in node.children(&mut node.walk()) {
        walk(child, source, out);
    }
}
```

The exact field names (`function`, `arguments`) depend on the
existing code. Read the current `extractors/elixir.rs` to see what
fields are used for `def` and mirror the pattern.

### 3.5 The Elixir-side normalization (probably no change)

In `lib/delfos/parsers/treesitter/tree_sitter.ex`, the
`normalize_symbol/2` function maps raw NIF output to delfos's
internal `Symbol` struct. Verify it doesn't have a `case kind do
"function" -> ... ; _ -> :unknown end` pattern that would clobber
"module". If it does, add an explicit `"module" -> "module"` clause.

If `delfos/parsers/treesitter/tree_sitter.ex` line ~110 has
`@supported_languages` (it does, as we saw in earlier sessions),
verify "module" is in the kinds it expects (it is — see line 84 of
graph_builder.ex).

### 3.6 Rust toolchain requirements

The NIF is built with Rustler. The Rust toolchain is already set
up (this is verified by the fact that `mix compile` produces a
working `libtree_sitter_nif.so`). The NIF rebuilds automatically
when `mix compile` is run after a Rust source change. To force a
clean rebuild:

```bash
cd ~/cacafuti/delfos
mix deps.clean tree_sitter_nif --build  # forces NIF rebuild
# or:
MIX_ENV=dev mix compile --force
```

### 3.7 Build the binary

```bash
cd ~/cacafuti/delfos
mix batamanta           # produces ./delfos (97MB ELF binary)
cp ./delfos ~/bin/delfos  # install
~/bin/delfos --version    # should print "Delfos v2.2.0"
```

`mix batamanta` invokes `mix release --overwrite` internally and
bundles the result with `bat_pkg_*` and `batamanta-*` workdirs in
`/tmp/`. The NIF MUST be present in the release's `priv/native/`
directory. After `mix batamanta`, verify:

```bash
ls -la _build/prod/rel/delfos/lib/delfos-2.2.0/priv/native/libtree_sitter_nif.so
file ~/bin/delfos
# Should be: ELF 64-bit LSB pie executable, x86-64
```

### 3.8 End-to-end test

```bash
cd ~/cacafuti/delfos
mix run -e '
Application.ensure_all_started(:delfos)
alias Delfos.{Repo, Schema}
import Ecto.Query
Repo.delete_all(Schema.Relationship)
Repo.delete_all(Schema.FileMetrics)
Repo.delete_all(Schema.Chunk)
Repo.delete_all(Schema.Summary)
Repo.delete_all(Schema.Symbol)
Repo.delete_all(Schema.File)
Repo.delete_all(Schema.Project)
IO.puts "wiped"
'

# Re-init the delfos project
rm -f ~/cacafuti/delfos/xref_graph.dot
timeout 600 ~/bin/delfos init ~/cacafuti/delfos 2>&1 | tail -3

# Verify modules are now in the DB
mix run -e '
Application.ensure_all_started(:delfos)
{:ok, %{rows: kinds}} = Ecto.Adapters.SQL.query(Delfos.Repo, "SELECT kind, COUNT(*) FROM symbols GROUP BY 1 ORDER BY 2 DESC")
IO.inspect kinds, label: "kinds"
'
# Expected: [{function, ~200}, {module, ~170}, ...]
```

### 3.9 Edge cases to handle

- Nested modules: `defmodule Parent do; defmodule Child do; end; end`
  should produce two symbols, one for Parent and one for Child,
  with `qualified_name: "Parent.Child"` for the inner one.
- Module without explicit `do`: `defmodule Foo, do: nil` (single-line)
  → still extract a module symbol.
- Module with `use` / `@` attributes: don't extract those as
  separate symbols, but include the source in `content` of the
  module.
- Already known: function names like `definition` appearing in
  `lib/delfos/syntax/*.ex` line 4 — make sure the module `Syntax.Foo`
  is also captured (it might be at line 1, not line 4).

---

## 4. Test plan cross-reference

Re-run the relevant section of [TEST_PLAN.md](./TEST_PLAN.md) after
the fix:

| Test | Section | What to check |
|------|---------|----------------|
| T4.3  | §4.3 | `delfos init ~/cacafuti/delfos` should produce 367+ symbols (was 371, +170 with modules) |
| T6.x  | §6   | `delfos query "Delfos.CLI"` should match the module by qualified_name |
| T7.1  | §7.1 | `delfos audit` should show both functions and modules in QUALITY INDEX |
| T9.2  | §9.2 | `delfos explain Delfos.CLI.main/1` should still work (now finds the module) |
| T10.x | §10  | `delfos graph` should show the file → module → functions hierarchy |

The full E2E re-run command (with LLMs up, DB wiped):

```bash
export PATH=/usr/lib/ollama:$PATH
nohup llama-run embed > /tmp/delfos_llm_logs/embed.log 2>&1 &
nohup llama-run gpt-oss medium > /tmp/delfos_llm_logs/gpt_oss.log 2>&1 &
# Wait for both to respond 200 on /v1/models

cd ~/cacafuti/delfos
# Wipe DB
mix run -e 'Application.ensure_all_started(:delfos); alias Delfos.{Repo, Schema}; Repo.delete_all(Schema.Project); IO.puts "wiped"'

# Re-init
timeout 600 ~/bin/delfos init ~/cacafuti/delfos 2>&1 | grep -E "Indexed|edges|xref|cycle" | head -5

# Sanity check the kinds
mix run -e '
Application.ensure_all_started(:delfos)
{:ok, %{rows: kinds}} = Ecto.Adapters.SQL.query(Delfos.Repo, "SELECT kind, COUNT(*) FROM symbols GROUP BY 1")
IO.inspect kinds
'
# Must show {function, ~200} and {module, ~170}

# Other sanity checks
mix run -e '
Application.ensure_all_started(:delfos)
{:ok, %{rows: [[f]]}} = Ecto.Adapters.SQL.query(Delfos.Repo, "SELECT COUNT(*) FROM files")
{:ok, %{rows: [[c]]}} = Ecto.Adapters.SQL.query(Delfos.Repo, "SELECT COUNT(*) FROM chunks WHERE embedding IS NOT NULL")
{:ok, %{rows: [[r]]}} = Ecto.Adapters.SQL.query(Delfos.Repo, "SELECT COUNT(*) FROM relationships")
IO.puts "files=#{f} chunks_embedded=#{c} relationships=#{r}"
'
```

---

## 5. Things that are NOT the bug (don't fix)

- The `DateTime.compare/2` typo: already fixed in commit 16448f0 (uses
  `DateTime.diff/3` now). The `is_file_fresh?` function compares mtime
  to `DateTime.utc_now()` in UTC.
- The relationships schema: already extended in commit 5d7eee7
  (migration 20260708000002) with file-level support.
- The MCP preload bug in `get_callers_full/1` and `get_callees_full/1`:
  already fixed in commit 5d7eee7 (uses `assoc(r, :from)` and
  `preload: [from: :file]`).
- The opencode integration: confirmed working end-to-end with
  `opencode run` calling `delfos_search` and `delfos_symbol`.

If you find yourself "fixing" any of these, you're looking at the
wrong code path. The only remaining work is the NIF for module
extraction.

---

## 6. Out of scope (do NOT do in this task)

- Don't add new tests for functionality other than module extraction
- Don't refactor the existing function extractor
- Don't change the Elixir-side `normalize_symbol/2` unless the NIF
  is returning `kind: "module"` and it's being clobbered downstream
- Don't add new MCP tools or change existing tool contracts
- Don't touch the opencode integration or any other integrate command
- Don't update the CHANGELOG (that's a separate task)

---

## 7. Definition of Done

1. `mix batamanta` produces a `delfos` binary at `~/bin/delfos` that
   reports `Delfos v2.2.0`.
2. `delfos init ~/cacafuti/delfos` produces a DB with `module` symbols
   (at least ~170 for the delfos project itself).
3. The kinds distribution is approximately `{function, ~200}, {module, ~170}`.
4. `mix test test/delfos/parser/symbol_extraction_test.exs` (if it
   exists) passes for the module case.
5. The `delfos` binary can be re-built with `mix batamanta` and
   doesn't show regressions in the kinds distribution for the
   other languages (Rust struct still works).
6. The `mcp search` and `mcp symbol` tools still return proper
   results for the existing 371 symbols (no regression in
   function/struct extraction).

---

## 8. Commit message template

When you commit the fix, follow the existing commit style (see
`git log --oneline` for examples). Suggested:

```
fix(parser): extract Elixir 'defmodule' as kind=module symbols

The Rust NIF was only extracting def/defp/defmacro as functions.
Add a defmodule branch that walks (call function: "defmodule" ...)
and emits a symbol with kind="module", name=alias_text,
line_start=row, line_end=last_row.

Fixes: TEST_PLAN.md T4.3 expectation (367 symbols → now 540+ for
delfos project). Audited via DB query: symbol kinds distribution
should be ~200 function + ~170 module after the fix.

Verified: full init+query flow works through opencode MCP,
no regressions in function extraction, tree-sitter Rust struct
detection still works (1 struct, 6 functions in native/.../lib.rs).
```

Don't commit if:
- The kinds distribution shows regression in function/struct counts
- `mix test` breaks
- The binary fails to build or crashes on startup
- `opencode mcp list` shows delfos as "failed" instead of "connected"

---

## 9. Reference files

- `native/tree_sitter_nif/src/lib.rs` — main NIF dispatcher
- `native/tree_sitter_nif/src/extractors/elixir.rs` — ★ fix here
- `lib/delfos/parsers/treesitter/tree_sitter.ex` — Elixir-side wrapper (verify only)
- `lib/delfos/schema/symbol.ex` — `kind` field accepts: `function`, `module`, `class`, `macro`, `struct`, `trait`, `interface`
- `lib/delfos/indexer/graph_builder.ex:84` — query that filters by kind (will automatically include `module` once NIF returns it)
- `docs/TEST_PLAN.md` — E2E test plan
- `lib/delfos/mcp/tools.ex` — MCP tools (don't change)
- `lib/delfos/schema/relationship.ex` — relationships schema (don't change)

---

## 10. Working environment

- Elixir 1.19.5 (via asdf)
- Erlang 28.0
- Postgres 17 + pgvector 0.8.4 (Docker container, port 5432, db `delfos_prod`)
- Llama-server binaries at `~/bin/llama-server` (in `/usr/lib/ollama/`)
- Models: `~/models/gguf/Qwen3-Embedding-8B-Q4_K_M.gguf`, `~/models/gguf/gpt-oss-20b-UD-Q6_K_XL.gguf`
- Port 9998 = embed, port 9999 = chat (gpt-oss medium)

To start LLMs:
```bash
export PATH=/usr/lib/ollama:$PATH
nohup llama-run embed > /tmp/embed.log 2>&1 &
nohup llama-run gpt-oss medium > /tmp/gpt_oss.log 2>&1 &
# wait ~30s for both to be ready
```

Key API key: `sk-local-dev-key` (matches the actual llama-server
key, despite `register-local-llms` writing `sk-local-dev` by default
in earlier versions — see commit history for the fix).

---

*Document created as a single source of truth. If the NIF is fixed
in a different way or the spec changes, update this document to
match reality.*
