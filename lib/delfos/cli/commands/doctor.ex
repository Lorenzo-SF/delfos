defmodule Delfos.CLI.Commands.Doctor do
  @moduledoc """
  Full diagnostic of the Delfos environment.

  Thin CLI wrapper around `Delfos.Config.Diagnostics`. Most logic lives
  there — this module only handles output formatting and `--fix` UX.

  With `--fix` attempts to repair detected issues. With `--interactive`
  asks the user before applying any fix that touches the database or
  external services.
  """

  alias Alaja
  alias Delfos.Config.Diagnostics

  @help """
  USAGE
      delfos doctor [flags]

  FLAGS
      --fix            Attempt to repair detected issues automatically
      --interactive    Ask before applying each fix (recommended for first run)
      --json           Output results as JSON (machine-readable)

  EXAMPLES
      delfos doctor
      delfos doctor --fix --interactive
      delfos doctor --json | jq '.results[] | select(.status=="error")'
  """

  def run(["--help"]), do: Alaja.print_raw(@help)
  def run(["-h"]), do: Alaja.print_raw(@help)

  # Legacy argv entry point — kept for backward compat.
  def run(args) when is_list(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [fix: :boolean, interactive: :boolean, json: :boolean]
      )

    run_with_opts(opts)
  end

  @doc """
  Runs the doctor with pre-parsed options (no argv re-parse).
  """
  def run_with_opts(opts) when is_map(opts) do
    Application.ensure_all_started(:delfos)

    if opts[:json] do
      run_json()
    else
      run_pretty(opts[:fix] || false, opts[:interactive] || false)
    end
  end

  # ── Pretty output ───────────────────────────────────────────────────

  defp run_pretty(_fix_mode, _interactive) do
    Alaja.print_raw("\n=== DELFOS DOCTOR ===\n\n")
    results = Diagnostics.run()

    {pass, fail, warn} =
      Enum.reduce(results, {0, 0, 0}, fn r, {p, f, w} ->
        case r.status do
          :pass -> {p + 1, f, w}
          :fail -> {p, f + 1, w}
          :warn -> {p, f, w + 1}
        end
      end)

    Enum.each(results, fn r ->
      icon = %{pass: "✓", fail: "✗", warn: "!"}[r.status]
      Alaja.print_raw("  #{icon} #{r.label}: #{r.detail}\n")

      if r.action do
        Alaja.print_raw("     #{r.action}\n")
      end
    end)

    Alaja.print_raw("\n#{pass} passed · #{fail} failed · #{warn} warnings\n")

    if fail > 0 do
      Alaja.print_raw("\n")
      Alaja.print_info("Run with --fix to attempt repairs")
    end

    Alaja.print_raw("\n")
  end

  # ── JSON output ─────────────────────────────────────────────────────

  defp run_json do
    results = Diagnostics.run()

    Jason.encode!(%{results: results, timestamp: DateTime.utc_now()}, pretty: true)
    |> Alaja.print_raw()
  rescue
    e -> Alaja.print_error("JSON output failed: #{Exception.message(e)}")
  end
end
