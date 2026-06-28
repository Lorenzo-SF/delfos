defmodule Delfos.Syntax.C do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "C",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        auto break case char const continue default do double else
        enum extern float for goto if inline int long register
        restrict return short signed sizeof static struct switch
        typedef union unsigned void volatile while
      )),
      types: MapSet.new(~w(
        int char float double void long short signed unsigned
        size_t FILE uint8_t uint16_t uint32_t uint64_t int8_t
        int16_t int32_t int64_t bool
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "++",
          "--",
          "->",
          "<<",
          ">>",
          "&&",
          "||",
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
          "..",
          "...",
          "?",
          ":",
          "=",
          "->",
          "&"
        ]),
      specials: [
        %Special{
          pattern: ~r/#\s*include|#\s*define|#\s*ifdef|#\s*ifndef|#\s*endif|#\s*pragma|#\s*undef/,
          type: :decorator,
          priority: 5
        }
      ],
      module_separator: "->",
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
        plain: {:white, []}
      }
    }
  end
end
