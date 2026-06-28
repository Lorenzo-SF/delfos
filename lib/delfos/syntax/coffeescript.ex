defmodule Delfos.Syntax.CoffeeScript do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "CoffeeScript",
      line_comment: "#",
      block_comment: %{start: "###", end: "###"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        do let if else unless then not and or true false yes no on off
        null undefined this super new delete typeof instanceof in of by
        when while loop for in for own for all break continue return throw
        try catch finally switch case default extend import export from as
      )),
      types: MapSet.new(~w(
        number string boolean array object function date regexp class error symbol
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "->",
          "...",
          "..",
          "%%",
          "//",
          "**",
          "&&",
          "||",
          "&=",
          "|=",
          "^=",
          "<<=",
          ">>=",
          ">>>=",
          "?.",
          "?::",
          "?=",
          "||=",
          "&&=",
          "//=",
          "**=",
          "//",
          "%",
          "**",
          "=>",
          "=",
          "->",
          "::"
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
