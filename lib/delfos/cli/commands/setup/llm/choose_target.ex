defmodule Delfos.CLI.Commands.Setup.LLM.ChooseTarget do
  @moduledoc false

  alias Alaja.Printer.Interactive

  # `:both` is accepted from opts (e.g. `delfos config setup llm --both`)
  # but the interactive menu only shows llm/embedding/skip — `:both`
  # cannot come from the prompt itself. This asymmetry is intentional:
  # interactive users configure one thing at a time, programmatic callers
  # can ask for both in one go.
  @targets [:llm, :embedding, :both, :skip]

  @doc false
  def choose(opts \\ []) do
    case Keyword.get(opts, :target) do
      target when target in @targets ->
        target

      _ ->
        Interactive.question_with_options(
          "What do you want to configure?",
          [
            {"LLM chat endpoint", :llm},
            {"Embedding endpoint", :embedding},
            {"Skip — I'll configure later", :skip}
          ],
          color: :cyan,
          default: 3
        )
    end
  end
end
