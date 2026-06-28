defmodule Delfos.Syntax.GraphQL do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "GraphQL",
      line_comment: "#",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        query mutation subscription fragment on type interface
        union enum input scalar extend directive implements
        repeatable schema true false null
      )),
      types: MapSet.new(~w(
        Int Float String Boolean ID
      )),
      operators:
        MapSet.new([
          "=",
          ":",
          "!",
          "&",
          "|",
          "@",
          "...",
          "->",
          ".."
        ]),
      specials: [
        %Special{pattern: ~r/@\w+/, type: :decorator, priority: 10}
      ],
      module_separator: ".",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        operator: {:white, []},
        module: {:magenta, []},
        decorator: {:yellow, []},
        builtin: {:cyan, []},
        macro: {:magenta, [:bold]},
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
