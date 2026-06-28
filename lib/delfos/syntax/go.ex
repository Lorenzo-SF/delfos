defmodule Delfos.Syntax.Go do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Go",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/`/, end: ~r/`/, escape: false},
        %{delim: ~r/r"/, end: ~r/"/, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u|i)?\b/,
      keywords: MapSet.new(~w(
        break case chan const continue default defer else
        fallthrough for func go goto if import interface
        map package range return select struct switch type
        var
      )),
      types: MapSet.new(~w(
        bool byte complex64 complex128 error float32 float64
        int int8 int16 int32 int64 rune string uint uint8
        uint16 uint32 uint64 uintptr
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "->",
          "++",
          "--",
          "<<",
          ">>",
          "&&",
          "||",
          ":=",
          "&^",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "<-",
          "&",
          "|",
          "^",
          "!"
        ]),
      specials: [
        %Special{pattern: ~r/^package\s+\w+/, type: :keyword, priority: 10},
        %Special{pattern: ~r/^import\s+/, type: :keyword, priority: 10}
      ],
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        operator: {:white, []},
        plain: {:white, []}
      }
    }
  end
end
