defmodule Delfos.Parsers.NIFStatus do
  @moduledoc """
  Reports whether the tree-sitter NIF actually loaded.

  Rustler-compiled NIFs register a stub function that raises
  `:nif_not_loaded` when the underlying .so isn't loadable (missing
  shared library, wrong arch, kernel mismatch, etc.). The "module is
  loaded" check (`Code.ensure_loaded?/1`) is not sufficient — it only
  tells us the Elixir module compiled, not whether the Rust side
  actually wired up.

  Usage:

      case Delfos.Parsers.NIFStatus.loaded?() do
        true ->
          # ... use the NIF
        false ->
          # ... fall back to regex or abort with a clear error
      end

  ## Why this matters

  Pre-v2.6.0, `delfos mcp` would start successfully even when the
  NIF failed to load — the supervisor tree started, the Pulsar
  splash rendered, the receive loop began — but every parsing tool
  silently fell back to regex parsing. Worse, some tools returned
  confusing `FunctionClauseError`s or empty results with no
  explanation.

  In v2.6.0 the MCP server checks this at boot and either:

  1. Aborts cleanly with a clear error to stderr (the MCP client
     sees the process exit with non-zero status, which is preferable
     to silently producing wrong results), or
  2. Logs a prominent warning and continues with regex fallback (when
     the user explicitly opts in via the `regex_fallback: true` config
     key).

  ## Probing strategy

  `loaded?/0` calls `Delfos.Parsers.TreeSitter.NIF.supported_languages/0`
  inside a `try/rescue`. If the NIF loaded, this returns a list of
  ~36 language atoms. If not, it raises `(ArgumentError|:nif_not_loaded)`
  or similar and we treat that as "not loaded".

  The probe is O(1) — no IO, no DB. Safe to call on every command.
  """

  @doc """
  Returns true if the tree-sitter NIF is loaded and callable.
  """
  @spec loaded?() :: boolean()
  def loaded? do
    try do
      _ = Delfos.Parsers.TreeSitter.NIF.supported_languages()
      true
    rescue
      _ -> false
    catch
      _, _ -> false
    end
  end

  @doc """
  Returns a one-line status string for `delfos version` / diagnostics.

  Format: "loaded" | "NOT LOADED (regex fallback active)"
  """
  @spec status() :: String.t()
  def status do
    if loaded?(), do: "loaded", else: "NOT LOADED (regex fallback active)"
  end

  @doc """
  Returns true if the NIF is loaded, or if the user has explicitly
  opted in to regex fallback via config (`:delfos, :regex_fallback,
  true`). Used by MCP server's boot-time decision: abort on NIF
  failure unless the user accepts degraded parsing.
  """
  @spec acceptable?() :: boolean()
  def acceptable? do
    loaded?() or Application.get_env(:delfos, :regex_fallback, false)
  end
end
