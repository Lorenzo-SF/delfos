defmodule Delfos.CLI.Commands.Setup.LLM.ChooseTarget do
  @moduledoc false

  alias Alaja.Printer.Interactive

  @targets [:llm, :embedding, :skip]

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
