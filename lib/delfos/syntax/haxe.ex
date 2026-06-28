defmodule Delfos.Syntax.Haxe do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Haxe",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(e[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        function var if else while for do switch case default break continue
        return class interface extends implements typedef enum abstract macro
        override dynamic static public private inline extern final override
        callback true false null in cast new this super throw try catch
        trace untyped import using package
      )),
      types: MapSet.new(~w(
        Int Float Bool String Void Dynamic Array Map List Null Never any
        Enum ValueType Class Enum
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
          "&&",
          "||",
          "!",
          "&",
          "|",
          "^",
          "~",
          "<<",
          ">>",
          ">>>",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "<<=",
          ">>=",
          ">>>=",
          "++",
          "--",
          "?",
          ":",
          "=",
          "."
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
