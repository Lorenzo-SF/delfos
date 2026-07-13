# Plan for `@delfos` (Meta‑Toolchain & Release Orchestrator)

> **Goal** – Modularise the existing mix aliases, standardise the `mix install` flow across all projects, and upgrade documentation for Tree‑Sitter and Rust integration.

---

## 1. Preparation

| Step | Action | Outcome |
|------|--------|---------|
| 1.1 | Verify clean `fix-tools-domains` branch |
| 1.2 | `mix deps.get` – local override for all peers |
| 1.3 | Confirm `delfos/mix.exs` has `path:` overrides and that `batamanta` is correctly configured (release‑type `:release`).
| 1.5 | Commit any pending changes in this repo before starting modifications |

## 2. Implementation

| Target | Task |
|--------|------|
| **Task Refactor** | Move long alias definitions into dedicated modules: `Delfos.Tasks.Gen`, `Delfos.Tasks.Deploy`, `Delfos.Tasks.Lint`. |
| **Install Flow** | Add new mix task `delfos install` that runs batamanta, builds the binary, copies to `~/bin/delfos`, and updates `.tool‑versions`.
| **Documentation** | Create `docs/MCP_TOOLS.md` and reference it from README. |
| **Flavoring** | Ensure that `delfos` can be built both as an escript and as a release; adjust `releases` accordingly.

## 3. Tests

| Test File | Coverage Goal | Checks |
|-----------|---------------|-------|
| `test/delfos/install_test.exs` | 100 % | • `mix install` creates `~/bin/delfos`
| | | • Restores correct permissions
| `test/delfos/cli_test.exs` | 100 % | • CLI works ONCE binary is installed

Run `mix test --cover`.

## 4. Documentation

* Update `README.md` to emphasise the new `install` mix task.
* Update `CHANGELOG.md` with an entry ``Re‑architected delfos build system``.
* Ensure `docs/MCP_TOOLS.md` reflects the new tasks.

## 5. Quality

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict --format=json
mix test --cover
mix dialyzer
```

## 6. Commit & Push

```bash
git add -A
git commit -m "Re‑architect delfos build and install workflow"
git push origin fix-tools-domains
```

---

**End of plan for `@delfos`**