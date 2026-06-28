defmodule Delfos.Syntax.PureScript do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "PureScript",
      line_comment: "--",
      block_comment: %{start: "{-", end: "-}"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        module where let in do ado case of if then else true false
        data type newtype class instance derive foreign import infix
        infixl infixr as kind role
      )),
      types: MapSet.new(~w(
        Int Number Boolean String Char Array Unit Void
        Maybe Either Tuple Ordering List Map Set
        Foldable Functor Applicative Monad Semigroup Monoid
      )),
      operators:
        MapSet.new([
          "==",
          "/=",
          "<=",
          ">=",
          "=>",
          "<-",
          "->",
          "::",
          "$",
          "<<",
          ">>",
          "<$>",
          "<*>",
          "<$",
          "<*",
          "*>",
          "<|>",
          "<>",
          "<=",
          "<",
          ">=",
          ">",
          "||",
          "&&",
          "+",
          "-",
          "*",
          "/",
          "^",
          ".",
          "..",
          "#",
          "~>",
          "|>"
        ]),
      specials: [
        %Special{pattern: ~r/^foreign import/, type: :keyword, priority: 5}
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
