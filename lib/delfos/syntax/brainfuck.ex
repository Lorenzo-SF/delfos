defmodule Delfos.Syntax.Brainfuck do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Brainfuck",
      line_comment: "",
      strings: [],
      keywords: MapSet.new(),
      types: MapSet.new(),
      operators: MapSet.new(),
      specials: [
        %Special{pattern: ~r/[><+\-.,\[\]]/, type: :keyword, priority: 10}
      ],
      module_separator: "",
      colors: %{
        keyword: {:blue, [:bold]},
        plain: {:bright_black, [:italic]}
      }
    }
  end
end
