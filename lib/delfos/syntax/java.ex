defmodule Delfos.Syntax.Java do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Java",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true},
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|d|l|F|D|L)?\b/,
      keywords: MapSet.new(~w(
        abstract assert break case catch class const continue
        default do else enum extends final finally for goto if
        implements import instanceof interface native new package
        private protected public record return static strictfp
        super switch synchronized this throw throws transient
        try var void volatile while sealed permits
      )),
      types: MapSet.new(~w(
        boolean byte char double float int long short void
        String Object Class Throwable Exception RuntimeException
        Error Iterable Comparable List Set Map Collection
        ArrayList HashMap HashSet Optional Stream
        Integer Boolean Character Double Float Long Short
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "->",
          "::",
          "++",
          "--",
          "<<",
          ">>",
          ">>>",
          "&&",
          "||",
          "instanceof",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "&",
          "|",
          "^",
          "~",
          "!"
        ]),
      specials: [
        %Special{pattern: ~r/@\w+(\.\w+)*(\([^)]*\))?/, type: :decorator, priority: 10}
      ],
      module_separator: ".",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        decorator: {:yellow, []},
        operator: {:white, []},
        plain: {:white, []}
      }
    }
  end
end
