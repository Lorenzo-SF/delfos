defmodule Delfos.Syntax.Prolog do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Prolog",
      line_comment: "%",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      keywords: MapSet.new(~w(
        :- ?- -> :-- --> ; ! fail true false repeat
        abolish asserta assertz retract retractall clause
        call findall bagof setof functor arg =..
        name atom concat sub_atom member append select sort
        length maplist include exclude foldl foldr sumlist
        max_list min_list numlist between succ is mod div
      )),
      types: MapSet.new([]),
      operators:
        MapSet.new([
          ":-",
          "-->",
          "?-",
          ":+",
          ":?",
          ":->",
          ":<",
          ":>",
          ":>=",
          ":=",
          "is",
          "=",
          "\\=",
          "==",
          "\\==",
          "=:=",
          "=\\=",
          "<",
          ">",
          "=<",
          ">=",
          "=.."
        ]),
      specials: [
        %Special{pattern: ~r/[A-Z_]\w*/, type: :variable, priority: 10}
      ],
      module_separator: ":",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        variable: {:red, []},
        operator: {:white, []},
        module: {:magenta, []},
        decorator: {:yellow, []},
        builtin: {:cyan, []},
        plain: {:white, []}
      }
    }
  end
end
