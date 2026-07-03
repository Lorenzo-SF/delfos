defmodule Delfos.CLI.Commands.Setup do
  @moduledoc """
  Interactive setup wizard for Delfos.

  Guides the user through:

    1. Database — detect PostgreSQL (local / Docker), create DB, run migrations.
    2. LLM — choose provider (local / remote), select models, download via Candil.
    3. Configuration — write `~/.config/delfos/delfos.conf` with all choices.

  Called by `delfos doctor --fix` and also available standalone as
  `delfos setup`.
  """

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive

  alias Delfos.CLI.Commands.Setup.DB
  alias Delfos.CLI.Commands.Setup.LLM

  @help """
  USAGE
      delfos setup [SUBCOMMAND]

  SUBCOMMANDS
      (none)        Top-level wizard (DB and LLM choices)
      db            Jump straight to the database wizard
      llm           Jump straight to the LLM wizard
      --help        Show this help

  EXAMPLES
      delfos setup
      delfos setup db
      delfos setup llm
  """

  def run(opts \\ [])

  def run(args) when is_list(args) do
    case args do
      [] ->
        run_keyword([])

      ["--help"] ->
        Alaja.print_raw(@help)
        :ok

      ["db" | _rest] ->
        # `delfos setup db [opts]` jumps straight to the database
        # wizard. No top-level menu.
        Alaja.print_raw("\n")

        Header.print("Database setup",
          subtitle: "PostgreSQL + pgvector + migrations",
          color: {0, 180, 216}
        )

        Alaja.print_raw("\n")
        DB.run()

      ["llm" | _rest] ->
        # `delfos setup llm [opts]` jumps to the LLM wizard.
        Alaja.print_raw("\n")

        Header.print("LLM setup",
          subtitle: "Provider / model / endpoints",
          color: {0, 180, 216}
        )

        Alaja.print_raw("\n")
        LLM.run(force: true)

      # Legacy: also accepts keyword opts (used by `doctor --fix --interactive`)
      opts when is_list(opts) and opts != [] and is_atom(hd(opts)) ->
        run_keyword(opts)

      _ ->
        Alaja.print_warning("Unknown setup subcommand. Try:")
        Alaja.print_raw("  delfos setup db\n")
        Alaja.print_raw("  delfos setup llm\n")
        Alaja.print_raw("  delfos setup       # top-level wizard\n")
        :ok
    end
  end

  def run(opts) when is_list(opts) do
    run_keyword(opts)
  end

  defp run_keyword(opts) do
    Alaja.print_raw("\n")

    if opts[:llm_only] do
      llm_ok = LLM.run(force: true)
      db_ok = true
      Alaja.print_raw("\n")
      Header.print("SETUP COMPLETE", subtitle: summary_text(db_ok, llm_ok), color: {0, 200, 100})
    else
      Header.print("DELFOS SETUP WIZARD",
        subtitle: "Interactive setup assistant",
        color: {0, 180, 216}
      )

      Alaja.print_raw("\n")
      {db_ok, llm_ok} = show_config_menu()
      Alaja.print_raw("\n")
      Header.print("SETUP COMPLETE", subtitle: summary_text(db_ok, llm_ok), color: {0, 200, 100})
    end

    Alaja.print_raw("\n")
    Alaja.print_info("Next steps:")
    Alaja.print_raw("\n")
    Alaja.print_raw("  delfos init .    Index your first project\n")
    Alaja.print_raw("  delfos scan      Scan and embed all symbols\n")
    Alaja.print_raw("  delfos doctor    Verify everything is working\n")
    Alaja.print_raw("\n")
  end

  @doc "Solo LLM setup (para doctor --fix --interactive)"
  def run_llm_only, do: run(llm_only: true)

  defp show_config_menu do
    case Interactive.question_with_options(
           "What do you want to configure?",
           [
             {"1. LLM — provider, models, endpoints", :llm},
             {"2. Database — PostgreSQL and migrations", :db},
             {"3. Both — database and LLM", :both},
             {"n. Skip — I'll do it later", :skip}
           ],
           color: :cyan
         ) do
      :db ->
        {DB.run(), false}

      :llm ->
        {true, LLM.run(force: true)}

      :both ->
        {DB.run(), LLM.run()}

      :skip ->
        {false, false}

      :error ->
        Alaja.print_error("Invalid option")
        show_config_menu()
    end
  end

  @doc false
  def summary_text(true, true), do: "All systems ready"

  def summary_text(true, false),
    do: "Database OK, LLM setup incomplete — run again with --fix"

  def summary_text(false, true), do: "LLM OK, Database setup incomplete"

  def summary_text(false, false), do: "Both need attention"
end
