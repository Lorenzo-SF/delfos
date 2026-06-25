# Delfos MCP Tools — Reference

Delfos exposes 8 tools via the Model Context Protocol (JSON-RPC 2.0 over
stdio). The server runs with `delfos serve --mcp`. Each tool returns a
text payload designed for AI agent consumption — compact, structured,
information-dense.

## Tool index

| Tool | Purpose |
|------|---------|
| `delfos_search` | Hybrid search (vector + BM25 + graph) |
| `delfos_symbol` | Full symbol details with code + LLM summary |
| `delfos_context` | Compact context bundle for a task |
| `delfos_callers` | Who calls this symbol |
| `delfos_callees` | What this symbol calls |
| `delfos_impact` | BFS impact analysis |
| `delfos_audit` | Technical debt metrics |
| `delfos_files` | Indexed file structure |

---

## `delfos_search`

Find symbols, functions, modules, or any code entity via hybrid search.

**Input:**

```json
{
  "query": "JWT authentication",
  "kind": "function",        // optional
  "level": "chunk",          // optional: symbol | chunk | summary
  "limit": 5                 // optional, default 5
}
```

**Output:**

```
QUERY: JWT authentication | RESULTS: 5
[1] score=0.847 kind=function name=AuthController.verify_token/2
    src/auth/auth_controller.ex:84-112
[2] score=0.812 kind=function name=JwtService.decode/1
    src/auth/jwt_service.ex:23-58
[3] score=0.798 kind=module name=Auth.Guard
    src/auth/guard.ex
[4] score=0.751 kind=function name=Plug.Auth.verify/2
    deps/plug/lib/plug/auth.ex:140-201
[5] score=0.689 kind=function name=TokenStore.refresh/1
    src/auth/token_store.ex:67-95
```

---

## `delfos_symbol`

Full details of a single symbol — code, LLM summary, callers, callees,
risk metrics.

**Input:**

```json
{ "name": "AuthController.verify_token" }
```

**Output:**

```
SYMBOL: AuthController.verify_token/2
KIND: function | FILE: src/auth/auth_controller.ex:84 | LANG: elixir | VIS: public
SUMMARY: Validates JWT token from Authorization header, checks expiry
and issuer, then attaches :current_user to conn. Returns 401 on any
validation failure.
SPEC: verify_token(Plug.Conn.t(), nil | keyword()) :: Plug.Conn.t()
CALLERS(3): AuthControllerPlug.authenticate/2, AuthController.refresh/2, AuthController.logout/1
CALLEES(4): JwtService.decode/1, TokenStore.lookup/1, Logger.warning/1, Conn.send_resp/3
RISK: debt=4.2 instability=0.31 churn=12 cycle=false
RELATED: JwtService.decode/1 (0.92), Auth.Guard (0.87), PlugAuth (0.84)
CODE:
def verify_token(conn, _opts) do
  with {:ok, token} <- extract_token(conn),
       {:ok, claims} <- JwtService.decode(token),
       :ok <- validate_claims(claims) do
    assign(conn, :current_user, claims["sub"])
  else
    err ->
      Logger.warning("auth failed: #{inspect(err)}")
      conn |> send_resp(401, "unauthorized") |> halt()
  end
end
```

---

## `delfos_context`

Bundle of relevant symbols for a task description. Use as the first
call when starting work.

**Input:**

```json
{
  "task": "Add rate limiting to the login endpoint",
  "max_symbols": 8           // optional, default 8
}
```

**Output:**

```
TASK: Add rate limiting to the login endpoint

[RANK 1] AuthController.login/2 — src/auth/auth_controller.ex:45-78
  Summary: Validates credentials, creates session, returns token.
  Risk: debt=2.1 stable=true churn=8
  [code: ~600 chars]

[RANK 2] RateLimiter — src/rate_limiter.ex
  Summary: Token-bucket rate limiter with plug and genserver support.
  Risk: debt=1.0 stable=true churn=3

[RANK 3] Plug.RateLimit — deps/plug_rate_limit/lib/plug/rate_limit.ex
  Summary: ...

(… up to max_symbols entries, ordered by relevance)
```

---

## `delfos_callers`

Symbols that call the named one.

**Input:** `{ "name": "AuthController.verify_token" }`

```
CALLERS OF: AuthController.verify_token/2 (3)
  AuthControllerPlug.authenticate/2 — src/auth/auth_controller_plug.ex:31
  AuthController.refresh/2 — src/auth/auth_controller.ex:121
  AuthController.logout/1 — src/auth/auth_controller.ex:148
```

---

## `delfos_callees`

Symbols called by the named one.

**Input:** `{ "name": "AuthController.login" }`

```
CALLEES OF: AuthController.login/2 (5)
  UserRepo.find_by_email/1 — src/repos/user_repo.ex:18
  Bcrypt.verify_pass/2 — deps/bcrypt/lib/bcrypt.ex:42
  SessionStore.create/2 — src/auth/session_store.ex:55
  TokenStore.issue/1 — src/auth/token_store.ex:11
  Logger.info/1 — deps/logger/lib/logger.ex:91
```

---

## `delfos_impact`

BFS analysis — what symbols/files would be affected if you change this.

**Input:** `{ "name": "JwtService.decode", "depth": 3 }`

```
IMPACT OF: JwtService.decode/1 (depth=3)
  Direct callers (2): AuthController.verify_token, PlugAuth.verify
  Indirect (5): AuthRouter, SessionStore.refresh, ...
  Total: 7 symbols across 4 files
  Files at risk: src/auth/*.ex (3), deps/plug/lib/plug/auth.ex (1)
```

---

## `delfos_audit`

Technical-debt metrics: churn, cycles, instability, debt score.

**Input:** `{ }` for whole project, or `{ "file": "src/auth/auth_controller.ex" }` for one file.

```
PROJECT AUDIT — my-app
HOTSPOTS (top 5):
  src/legacy/payments.ex | churn=89 authors=7 risk=14.2
  ...
DEPENDENCY CYCLES: 2 files
  src/auth/auth_controller.ex ↔ src/auth/session_store.ex
HIGH TECHNICAL DEBT: 5 files
QUALITY: 87% symbols embedded, 41% summarised
```

---

## `delfos_files`

Indexed file structure.

**Input:** `{ "filter": "auth" }` (optional)

```
INDEXED FILES (filter=auth)
  src/auth/auth_controller.ex     elixir  187 lines  risk=4.2
  src/auth/jwt_service.ex         elixir   58 lines  risk=1.1
  src/auth/session_store.ex       elixir  102 lines  risk=3.5
  test/auth/auth_controller_test.exs  elixir  94 lines
```

---

## Format guarantees

- All tool responses are **plain text** (not JSON), designed to be
  parsed by an LLM line-by-line.
- Scores and metrics are floats rounded to 3 decimals.
- `code` blocks in `delfos_symbol` are truncated to 800 chars; use
  `delfos_search --level=chunk` for longer previews.
- File paths are always **relative to project root**, never absolute.
