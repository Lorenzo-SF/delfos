defmodule Delfos.Syntax.AppleScript do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "AppleScript",
      line_comment: "--",
      block_comment: %{start: "(*", end: "*)"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b\d+(\.\d+)?\b/,
      keywords: MapSet.new(~w(
        tell end to set get copy count repeat times while until if then else
        return display dialog display alert log choose file choose folder
        choose from list choose color set volume get volume settings beep
        delay launch run activate quit open reopen close save exists move
        copy duplicate delete make create offset word paragraph character
        text item number date
      )),
      types: MapSet.new(~w(
        integer real boolean string date list record file alias POSIX file
        text number
      )),
      operators:
        MapSet.new([
          "&",
          "^",
          "*",
          "/",
          "-",
          "+",
          "=",
          "<",
          "≤",
          "≥",
          ">",
          "≠",
          "=",
          "¬",
          "as",
          "div",
          "mod",
          "and",
          "or",
          "not",
          "starts",
          "with",
          "ends",
          "contains",
          "is",
          "in",
          "that"
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
