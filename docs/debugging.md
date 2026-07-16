# Delfos debugging tools

> Audience: Delfos maintainers and contributors debugging the indexer.
> Scope: this file documents **delfos-specific** debug helpers — it is
> not a generic tree-sitter tutorial.

Delfos exposes one NIF-backed diagnostic for inspecting what the
underlying tree-sitter grammars actually emit, plus a handful of
Elixir-side escape hatches used during incident investigation. This
file covers the most prominent of those: `dump_tree/2`.

---

## `Delfos.Parsers.TreeSitter.NIF.dump_tree/2`

Public debugging NIF that returns every **named** tree-sitter node for a
given source, with line numbers and a short text preview.

### Signature

```elixir
@spec dump_tree(language :: String.t(), source :: binary) ::
  {:ok, [%{required(binary) => term}]} | {:error, String.t()}
```

`language` is the same string list accepted by `parse_symbols/2`
(`"elixir"`, `"typescript"`, `"python"`, `"rust"`, etc. — see
`NIF.supported_languages/0`). `source` is the file contents as a binary.

### What the result looks like

On success the NIF returns a flat list, not a tree:

```elixir
{:ok, [%{"kind" => "call", "start_row" => 0, "end_row" => 2, "text_preview" => "..."}, ...]}
```

Each map has **string keys** (this is how the Rust encoder emits them):

| Key           | Type    | Meaning                                                                                |
|---------------|---------|----------------------------------------------------------------------------------------|
| `kind`        | binary  | The grammar node type, e.g. `"call"`, `"alias"`, `"identifier"`, `"binary_operator"`.  |
| `start_row`   | integer | 0-based row of the node's first byte.                                                  |
| `end_row`     | integer | 0-based row of the node's last byte (inclusive).                                       |
| `text_preview`| binary  | The node's source text, newlines collapsed to spaces, whitespace trimmed, capped at 60 chars. |

**"Named nodes"** are the ones tree-sitter marks with `is_named() == true`
— i.e. real AST nodes, not the anonymous tokens (whitespace, commas,
parens, the `def` keyword itself as a leaf). Type strings are entirely
grammar-specific. For Elixir you'll see `source`, `call`, `identifier`,
`arguments`, `alias`, `do_block`, `keywords`, `pair`, `keyword`, `atom`,
`binary_operator`, etc.

The function walks the tree depth-first with no depth limit. On a
typical 500-line Elixir file expect a few thousand entries; on very
large sources it can produce tens of thousands.

### Worked example (real output)

Verified output from `/tmp/tree_sitter_debug.txt` (TEST A), produced
by calling `dump_tree("elixir", src)` on the source below:

```elixir
iex> src = "defmodule Foo do\n  def bar, do: :ok\nend\n"
iex> {:ok, nodes} = Delfos.Parsers.TreeSitter.NIF.dump_tree("elixir", src)
iex> Enum.take(nodes, 5)
[
  %{"kind" => "source",     "start_row" => 0, "end_row" => 2, "text_preview" => "defmodule Foo do   def bar, do: :ok end"},
  %{"kind" => "call",       "start_row" => 0, "end_row" => 2, "text_preview" => "defmodule Foo do   def bar, do: :ok end"},
  %{"kind" => "identifier", "start_row" => 0, "end_row" => 0, "text_preview" => "defmodule"},
  %{"kind" => "arguments",  "start_row" => 0, "end_row" => 0, "text_preview" => "Foo"},
  %{"kind" => "alias",      "start_row" => 0, "end_row" => 0, "text_preview" => "Foo"}
]
```

Note how `call` spans the entire `defmodule Foo do ... end` (start_row
== 0, end_row == 2), the outer `arguments` node contains just `"Foo"`,
and inside that sits an `alias` node with the same preview. That double
`call → arguments → alias` shape is what the Bug #22 fix in
`native/tree_sitter_nif/src/lib.rs` had to thread through to extract
`defmodule Pote.Theme` correctly.

> Note on key style: the maps come out of the NIF with **binary
> string keys** (`"kind"`). To compare against atoms (`:kind`) Elixir
> need to call `Map.get(node, "kind")` (string) or normalize with
> `Map.new(node, fn {k, v} -> {String.to_atom(k), v} end)`. The
> `parse_symbols/2` wrapper already does this for you (see
> `normalize_symbol/2` in `lib/delfos/parsers/treesitter/tree_sitter.ex`).

### Why is each `defmodule` a `call`?

Tree-sitter-elixir 0.3.x models every keyword form (`def`, `defmodule`,
`defmacro`, `defp`, `if`, `case`, ...) as a generic `call` node whose
first child is an `identifier` carrying the keyword. The NIF's
`("elixir", "call")` match arms then pattern-match on that identifier to
decide whether the call is a function definition, a module definition,
or a macro. `dump_tree/2` shows you that identifier, which is exactly
what you need to see why the matcher rejected (or accepted) a node.

---

## When to use `dump_tree/2` vs. `parse_symbols/2`

| Use `dump_tree/2` when you want to...                                  | Use `parse_symbols/2` when you want to...                  |
|------------------------------------------------------------------------|-------------------------------------------------------------|
| See every node the grammar emits, in source order.                     | Get normalized `symbols`, `docs`, `todos` for the index.   |
| Debug why a particular symbol was (or was not) extracted.              | Index a project (`delfos scan`, `delfos init`).             |
| Inspect parent/child relationships while writing a grammar matcher.    | Get the `qualified_name` (`Module.fn`) for a file.          |
| Pick the right `kind` string when adding a new language.               | Get counts per `kind`.                                      |
| Confirm a tree-sitter upgrade changed node shapes.                     | Compare before/after a grammar upgrade on real source.      |

`dump_tree/2` is a **debug tool**. Do not call it from production code
paths, do not pipe its output into the indexer, and do not use it as a
substitute for `parse_symbols/2` — it walks every named node
recursively, has no pagination, and is intentionally slow.

---

## Origin

`dump_tree/2` was added by commit
[`887fcdc`](../native/tree_sitter_nif/src/lib.rs#L955) — *"debug(nif):
add dump_tree NIF + find Elixir 0.3 'arguments' is unfielded"* — while
investigating **Bug #22**. The investigation revealed that
tree-sitter-elixir 0.3.x emits the `arguments` node as an **unfielded**
named child of `call`, not as a field, so `child_by_field_name("arguments")`
returned `None` and `parse_symbols/2` produced an empty list. See
`docs/NIF_TREE_SITTER_MODULE_FIX.md` for the full write-up and
`CHANGELOG.md` (search *"Bug #22"* — entry under `[2.2.0] - 2026-07-08`)
for the release notes that record both the fix and the diagnostic.

The diagnostic was kept (instead of being deleted after the fix)
because it remains the fastest way to verify what a grammar is actually
emitting when a matcher behaves unexpectedly — common scenarios:

- *"Module X was indexed but Y was not"* — diff the dump of both files
  and look for the missing `identifier` / `alias` / `arguments` chain.
- *"The guard-clause extraction dropped a function"* — search the dump
  for a `binary_operator` node inside an `arguments` node (the
  Bug #22 follow-up fix in commit `5002054` added the helper that
  recurses into the left operand of that node).
- *"I added a new language and `parse_symbols` returns nothing"* —
  run `dump_tree` first to see what kinds the grammar emits, then
  decide whether to add a `("lang", "kind")` arm to the NIF's main
  extraction routine.

---

## Implementation notes for future maintainers

- **Rust location**: `dump_tree/2` is defined at
  `native/tree_sitter_nif/src/lib.rs` around line 955; the recursive
  helper `dump_named_nodes/4` sits a few lines above it.
- **Elixir stub**: declared at
  `lib/delfos/parsers/treesitter/tree_sitter.ex` line 7
  (`def dump_tree(_language, _source), do: :erlang.nif_error(:nif_not_loaded)`).
  The wrapper module currently does **not** call it from anywhere — it
  is a public surface only by virtue of the stub being public on
  `Delfos.Parsers.TreeSitter.NIF`.
- **Registered as a Rustler NIF**: the registration list at the bottom
  of `lib.rs` (around line 996) explicitly includes `dump_tree`. If
  you remove the NIF, delete both the registration entry and the Elixir
  stub, otherwise callers will get `:nif_not_loaded` at compile time.
- **`@moduledoc false`**: the stub module is intentionally
  undocumented in `@moduledoc`. Adding `@doc` strings here would
  advertise the helper to end users — we want it discoverable by
  maintainers but not by `iex h Delfos.Parsers.TreeSitter.NIF` from
  an application release. Refer people to this file instead.
- **Bounded previews only**: the `take(60)` in `dump_named_nodes` is
  intentional. Bumping it would make dump output unwieldy in REPL
  sessions without adding diagnostic value — the start/end rows are
  enough to locate the node in source.
- **Cost**: the function does a full AST walk with no memoisation.
  Treat it like `String.graphemes/2` for a multi-MB file: it will return,
  it will be slow, and you should not call it inside a hot loop.
- **A wrapper that's safe to keep**: if you want to remove the public
  stub while keeping the Rust helper available for ad-hoc debugging,
  move the Elixir stub into a `Delfos.Parsers.TreeSitter.NIF.Debug`
  namespace guarded by a `Mix.env() != :prod` check. Today neither has
  been done; the current shape is the smallest possible surface.

---

## Other debug escape hatches (brief)

These are not NIFs but are commonly reached for during incident
investigation. Listed here for discoverability, not for everyday use:

- **`LLMDiscovery`** — `~/bin/delfos status` shows endpoint health;
  `LlmDiscovery.start_link(force: true)` restarts and re-checks.
- **`mix audit`** — wrapper around `mix credo --strict` plus the
  repo-local `audit_delfos.txt` checks. Use when a refactor is suspected
  of introducing regressions.
- **`llama-server` directo** — arranca `llama-server` a mano (con los
  flags `-m`/`--port`/etc.) cuando el wrapper `~/bin/llama-run` es el
  problema y no el modelo en sí. El script `scripts/llm-server.sh` se
  eliminó en v2.3.0; este es el reemplazo canónico.
