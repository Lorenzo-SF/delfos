defmodule Delfos.Syntax.Gleam do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Gleam",
      line_comment: "//",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      keywords: MapSet.new(~w(
        let assert case if const fn type opaque import pub use as todo panic return
      )),
      types: MapSet.new(~w(
        Int Float Bool String List Tuple BitArray Result Option Nil
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "->",
          "=>",
          "<|",
          "|>",
          "..",
          "++",
          "<>",
          "&&",
          "||",
          "=",
          "|."
        ]),
      specials: [],
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
