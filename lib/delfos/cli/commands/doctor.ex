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
  alias Alaja.Components.Header
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
      run_pretty(opts[:fix] || false, opts[:interactive] || false)
    end
  end

  # ── Pretty output ───────────────────────────────────────────────────

  defp run_pretty(fix_mode, interactive) do
    Alaja.print_raw("\n=== DELFOS DOCTOR ===\n\n")
    results = Diagnostics.run()
    render_results(results)

    if fix_mode do
      Alaja.print_raw("\n")

      Header.print("APPLYING FIXES",
        subtitle: (interactive && "interactive mode") || "automatic mode",
        color: {255, 180, 0}
      )

      Alaja.print_raw("\n")

      {fixed, still_failing} = apply_fixes(results, interactive)
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

  defp apply_fixes(results, interactive) do
    failed = Enum.filter(results, &(&1.status == :error))

    {fixed, still_failing} =
      Enum.reduce(failed, {[], []}, fn r, {f_acc, s_acc} ->
        case try_fix(r, interactive) do
          :ok ->
            Alaja.print_success("  ✓ Fixed: #{r.name}")
            {[r.id | f_acc], s_acc}

          {:ok, msg} ->
            Alaja.print_success("  ✓ Fixed: #{r.name} (#{msg})")
            {[r.id | f_acc], s_acc}

          {:skipped, reason} ->
            Alaja.print_warning("  ↷ Skipped: #{r.name} (#{reason})")
            {f_acc, s_acc}

          {:error, reason} ->
            Alaja.print_error("  ✗ Could not fix: #{r.name} — #{reason}")
            {[r.id | s_acc], s_acc}
        end
      end)

    {Enum.reverse(fixed), Enum.reverse(still_failing)}
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

  # ── Fix dispatch ────────────────────────────────────────────────────

  defp try_fix(%{id: :config_file}, interactive) do
    if interactive do
      case Alaja.Printer.Interactive.question_with_options(
             "Regenerate config file from defaults?",
             [{"Yes", :yes}, {"No", :no}]
           ) do
        :yes -> do_fix_config_file()
        :no -> {:skipped, "user declined"}
      end
    else
      do_fix_config_file()
    end
  end

  defp try_fix(%{id: :encryption_key}, _interactive) do
    do_fix_encryption_key()
  end

  defp try_fix(%{id: :migrations}, interactive) do
    if interactive do
      case Alaja.Printer.Interactive.question_with_options(
             "Apply database schema (bootstrap.sql)?",
             [{"Yes", :yes}, {"No", :no}]
           ) do
        :yes -> do_fix_migrations()
        :no -> {:skipped, "user declined"}
      end
    else
      do_fix_migrations()
    end
  end

  defp try_fix(%{id: :postgres_installation}, interactive) do
    if interactive do
      case Alaja.Printer.Interactive.question_with_options(
             "Install PostgreSQL 17 + pgvector via Docker?",
             [{"Yes", :yes}, {"No", :no}]
           ) do
        :yes ->
          Delfos.Config.PostgresDiscovery.Installer.install()
          :ok

        :no ->
          {:skipped, "user declined"}
      end
    else
      Delfos.Config.PostgresDiscovery.Installer.install()
    end
  end

  defp try_fix(%{id: :database}, interactive) do
    case Delfos.Config.Bootstrap.ensure_database(yes: !interactive) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp try_fix(%{id: :pgvector}, _interactive) do
    # Enable via SQL — works whether the PG is local or Docker-managed.
    case Delfos.Config.Bootstrap.enable_pgvector() do
      :ok -> {:ok, "extension enabled"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp try_fix(%{id: :embed_provider}, interactive) do
    try_fix_provider(interactive)
  end

  defp try_fix(%{id: :llm_provider}, interactive) do
    try_fix_provider(interactive)
  end

  defp try_fix(_other, _interactive), do: {:skipped, "no automatic fix available"}

  defp try_fix_provider(interactive) do
    if interactive do
      case Alaja.Printer.Interactive.question_with_options("Configure LLM provider?", [
             {"Yes", :yes},
             {"No", :no}
           ]) do
        :yes ->
          Delfos.CLI.Commands.Setup.run_llm_only()
          :ok

        :no ->
          {:skipped, "user declined"}

        # question_with_options devuelve :error cuando stdin no es
        # interactivo (p.ej. pipe vacío). Sin esta cláusula el case
        # crashea con CaseClauseError. Tratamos :error como "no
        # respuesta del usuario" → skip silencioso con mensaje útil.
        :error ->
          {:skipped, "non-interactive stdin — run 'delfos config setup llm' manually"}
      end
    else
      {:skipped, "LLM setup requires --interactive or run 'delfos config setup llm'"}
    end
  end

  # ── Individual fix implementations ──────────────────────────────────

  defp do_fix_config_file do
    case Delfos.Config.Manager.ensure_config_exists_public() do
      :ok -> {:ok, "regenerated"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_fix_encryption_key do
    case Delfos.Config.Manager.ensure_encryption_key() do
      :ok -> {:ok, "key generated"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_fix_migrations do
    case Delfos.Config.Bootstrap.ensure_database(yes: true) do
      :ok ->
        {:ok, "bootstrap applied"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
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
