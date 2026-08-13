defmodule Delfos.CLI.Commands.Context do
  @moduledoc """
  Deprecated alias of `Delfos.CLI.Commands.Agents`.

  Kept for backward compatibility — `delfos context` was renamed to
  `delfos agents` in v2.3.0 because the original name was confusing
  (suggested "dynamic context for a symbol", which is what `--symbol`
  actually does). Old muscle memory and scripts continue to work; the
  CLI handler emits a one-line deprecation warning before forwarding.

  This module is the implementation behind `Delfos.CLI.context_handler/1`.
  It wraps `Agents.run/1` so unit tests can exercise the routing layer
  without going through the Alaja dispatcher.
  """

  alias Alaja
  alias Delfos.CLI.Commands.Agents

  @help """
  USAGE
      delfos context [flags]

  Generate AGENTS.md / CLAUDE.md from the index for AI agents.
  This command is deprecated; use `delfos agents` instead.

  FLAGS
      --output <dir>    Output directory (default: cwd)
      --symbol <name>   Show focused context for a specific symbol
                       (prints to stdout instead of writing files)
      --format <fmt>    Output format for --symbol: markdown (default) | json
  """

  @doc """
  Entry point matching the `Delfos.CLI.Commands.*` convention: receives a
  list of argv strings and forwards to `Agents.run/1`.
  """
  def run(["--help"]), do: Alaja.print_raw(@help)
  def run(["-h"]), do: Alaja.print_raw(@help)

  def run(args) when is_list(args) do
    Agents.run(args)
  end
end
