defmodule Delfos.Syntax.Kotlin do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Kotlin",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u|F|L|U)?\b/,
      keywords: MapSet.new(~w(
        abstract actual annotation as as? break by catch class
        companion const constructor crossinline data delegate do
        dynamic else enum expect export external false final finally
        for fun get if import infix init inline inner interface
        internal is lateinit let noinline null object open operator
        out override package private protected public reified return
        sealed set suspend super tailrec this throw true try
        typealias typeof val var vararg when where while yield
      )),
      types: MapSet.new(~w(
        Int Long Float Double Char Boolean String Unit Any Nothing
        Array List Set Map Pair Triple Byte Short UByte UShort UInt
        ULong
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "===",
          "!==",
          "<=",
          ">=",
          "!!",
          "?.",
          "?:",
          "::",
          "->",
          "=>",
          "+",
          "-",
          "*",
          "/",
          "%",
          "..",
          "in",
          "!is",
          "as",
          "as?",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&&",
          "||"
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
        plain: {:white, []}
      }
    }
  end
end
