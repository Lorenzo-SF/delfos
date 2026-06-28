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

  def run(opts \\ []) do
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
      :db -> {DB.run(), false}
      :llm -> {true, LLM.run(force: true)}
      :both -> {DB.run(), LLM.run()}
      :skip -> {false, false}
      :error ->
        Alaja.print_error("Invalid option")
        show_config_menu()
    end
  end

  defp summary_text(true, true), do: "All systems ready"
  defp summary_text(true, false), do: "Database OK, LLM setup incomplete — run again with --fix"
  defp summary_text(false, true), do: "LLM OK, Database setup incomplete"
  defp summary_text(false, false), do: "Both need attention"
end
