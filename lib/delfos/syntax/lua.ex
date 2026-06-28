defmodule Delfos.Syntax.Lua do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Lua",
      line_comment: "--",
      block_comment: %{start: "--[[", end: "]]"},
      strings: [
        %{delim: ~r/\[\[/, end: ~r/\]\]/, multiline: true, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        and break do else elseif end false for function goto if
        in local nil not or repeat return then true until while
      )),
      types: MapSet.new(~w(
        nil boolean number string table function thread userdata
      )),
      operators:
        MapSet.new([
          "==",
          "~=",
          "<=",
          ">=",
          "..",
          "...",
          "#",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "^=",
          "..=",
          "&&",
          "||",
          "~=",
          "//"
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
        macro: {:magenta, [:bold]},
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
