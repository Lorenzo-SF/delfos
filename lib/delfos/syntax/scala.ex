defmodule Delfos.Syntax.Scala do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Scala",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|d|F|L|D)?\b/,
      keywords: MapSet.new(~w(
        abstract case catch class def do else enum extends false
        final finally for forSome given if implicit import lazy
        match new null object override package private protected
        requires return sealed super this throw trait true try type
        val var while with yield macro
      )),
      types: MapSet.new(~w(
        Int Long Float Double Char Boolean String Unit Nothing Any
        AnyRef AnyVal Array List Set Map Option Either Try Future
        Seq IndexedSeq
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "<-",
          "<:",
          ">:",
          "<%",
          "<%@",
          "::",
          "#::",
          "##:",
          "++",
          ":::",
          ":::",
          "+:",
          "-:",
          "+",
          "-",
          "*",
          "/",
          "%",
          "&&",
          "||",
          "&",
          "|",
          "^",
          "~",
          "?",
          ":",
          "=",
          "->",
          "<%"
        ]),
      specials: [
        %Special{pattern: ~r/@\w+/, type: :decorator, priority: 10}
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
        macro: {:magenta, [:bold]},
        plain: {:white, []}
      }
    }
  end
end
