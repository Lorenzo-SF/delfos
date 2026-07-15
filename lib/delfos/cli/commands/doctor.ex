defmodule Delfos.CLI.Commands.Doctor do
  @moduledoc """
  Full diagnostic of the Delfos environment.

  Thin CLI wrapper around `Delfos.Config.Diagnostics`. Most logic lives
  there — this module only handles output formatting and `--fix` UX.

  With `--fix` attempts to repair detected issues. With `--guided`
  asks the user before applying any fix that touches the database or
  external services.
  """

  alias Alaja
  alias Alaja.Components.Header
  alias Delfos.Config.Diagnostics

  @help """
  USAGE
      delfos doctor [flags]

  FLAGS
      --fix         Attempt to repair detected issues automatically
      --guided      Ask before applying each fix (recommended for first run)
      --json        Output results as JSON (machine-readable)

  EXAMPLES
      delfos doctor
      delfos doctor --fix --guided
      delfos doctor --json | jq '.results[] | select(.status=="error")'
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  @doc """
  Runs the doctor with pre-parsed options (no argv re-parse).
  """
  def run_with_opts(opts) do
    # Acepta tanto maps (camino moderno via alaja doctor_handler) como
    # keyword lists (camino legacy via 'delfos config doctor' → run/1
    # → OptionParser.parse → keyword list). Antes solo aceptaba maps y
    # crasheaba con FunctionClauseError cuando se invocaba por la vía
    # legacy, dejando inútil el subcomando 'delfos config doctor'.
    opts = if is_map(opts), do: opts, else: Map.new(opts)

    Application.ensure_all_started(:delfos)

    if opts[:json] do
      run_json()
    else
      run_pretty(opts[:fix] || false, opts[:guided] || false)
    end
  end

  # ── Pretty output ───────────────────────────────────────────────────

  defp run_pretty(fix_mode, guided) do
    Alaja.print_raw("\n=== DELFOS DOCTOR ===\n\n")
    results = Diagnostics.run()
    render_results(results)

    if fix_mode do
      Alaja.print_raw("\n")

      Header.print("APPLYING FIXES",
        subtitle: (guided && "guided mode") || "automatic mode",
        color: {255, 180, 0}
      )

      Alaja.print_raw("\n")

      {fixed, still_failing} = apply_fixes(results, guided)
      render_fix_summary(fixed, still_failing)

      if still_failing > 0 do
        Alaja.print_raw("\n")
        Alaja.print_warning("Re-running diagnostics...")
        Alaja.print_raw("\n")
        results_after = Diagnostics.run()
        render_results(results_after)
      end
    end

    Alaja.print_raw("\n")
  end

  defp render_results(results) do
    {pass, fail, warn} =
      Enum.reduce(results, {0, 0, 0}, fn r, {p, f, w} ->
        case r.status do
          :ok -> {p + 1, f, w}
          :error -> {p, f + 1, w}
          :warning -> {p, f, w + 1}
        end
      end)

    Enum.each(results, fn r ->
      icon = %{ok: "✓", error: "✗", warning: "!"}[r.status]
      Alaja.print_raw("  #{icon} #{r.name}: #{r.message}\n")
    end)

    Alaja.print_raw("\n#{pass} passed · #{fail} failed · #{warn} warnings\n")
  end

  # ── Fix dispatch via Botica ──────────────────────────────────────────
  #
  # Los fix functions viven en Delfos.Config.Diagnostics.check_definitions/0.
  # Modo auto: Botica.Doctor.fix/1. Modo interactivo: pregunta + fix_one/2.

  defp apply_fixes(results, guided) do
    config = %{app_name: "delfos", checks: Diagnostics.check_definitions()}

    if guided do
      apply_fixes_interactive(results, config)
    else
      apply_fixes_auto(config)
    end
  end

  defp apply_fixes_auto(config) do
    case Botica.Doctor.fix(config) do
      {:ok, report} ->
        Enum.each(report.applied, fn id ->
          Alaja.print_success("  ✓ Fixed: #{id}")
        end)

        Enum.each(report.failed, fn {id, reason} ->
          Alaja.print_error("  ✗ Could not fix: #{id} — #{reason}")
        end)

        {report.applied, Enum.map(report.failed, fn {id, _} -> id end)}

      {:error, reason} ->
        Alaja.print_error("Fix runner failed: #{reason}")
        {[], []}
    end
  end

  defp apply_fixes_interactive(results, config) do
    failed_ids = Enum.map(Enum.filter(results, &(&1.status == :error)), & &1.id)

    {fixed, still_failing} =
      Enum.reduce(failed_ids, {[], []}, fn id, {fixed_acc, failing_acc} ->
        case ask_and_fix_one(id, config) do
          {:fixed, msg} ->
            Alaja.print_success("  ✓ #{msg}")
            {[id | fixed_acc], failing_acc}

          {:skipped, reason} ->
            Alaja.print_warning("  ↷ Skipped: #{id} (#{reason})")
            {fixed_acc, failing_acc}

          {:error, reason} ->
            Alaja.print_error("  ✗ Could not fix: #{id} — #{reason}")
            {fixed_acc, [id | failing_acc]}
        end
      end)

    {Enum.reverse(fixed), Enum.reverse(still_failing)}
  end

  defp ask_and_fix_one(check_id, config) do
    prompt = fix_prompt(check_id)

    cond do
      prompt ->
        case Alaja.Printer.Interactive.question_with_options(prompt, [
               {"Yes", :yes},
               {"No", :no}
             ]) do
          :yes -> run_single_fix(check_id, config)
          :no -> {:skipped, "user declined"}
          :error -> {:skipped, "non-interactive stdin"}
        end

      true ->
        run_single_fix(check_id, config)
    end
  end

  defp fix_prompt(:config_file), do: "Regenerate config file from defaults?"
  defp fix_prompt(:postgres_installation), do: "Install PostgreSQL 17 + pgvector via Docker?"
  defp fix_prompt(:migrations), do: "Apply database schema (bootstrap.sql)?"
  defp fix_prompt(:database), do: "Apply database schema?"
  defp fix_prompt(:embed_provider), do: "Configure LLM provider for embeddings?"
  defp fix_prompt(:llm_provider), do: "Configure LLM provider for chat?"
  defp fix_prompt(_), do: nil

  defp run_single_fix(check_id, config) do
    case Botica.Repair.Fixer.fix_one(config, check_id) do
      {:ok, :applied} -> {:fixed, "#{check_id} fixed"}
      {:ok, :skipped} -> {:skipped, "no fix needed"}
      {:ok, :failed} -> {:error, "fix failed for #{check_id}"}
      {:error, reason} -> {:error, reason}
      other -> {:error, inspect(other)}
    end
  end

  defp render_fix_summary(fixed, still_failing) do
    Alaja.print_raw("\n")

    if fixed != [] do
      Alaja.print_success("Fixed #{length(fixed)} issue(s): #{Enum.join(fixed, ", ")}")
    end

    if still_failing != [] do
      Alaja.print_error(
        "#{length(still_failing)} issue(s) still failing: #{Enum.join(still_failing, ", ")}"
      )
    end
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
