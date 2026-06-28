defmodule Delfos.Syntax.Swift do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Swift",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/\#"/, end: ~r/"/, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u|F|L|U)?\b/,
      keywords: MapSet.new(~w(
        associatedtype async await break case catch class continue
        convenience default defer deinit didSet do dynamic else
        enum extension fallthrough false fileprivate final for func
        get guard if import in indirect infix init inout internal
        is lazy let mutating nonmutating open operator optional
        override package postfix precedence prefix private protocol
        public repeat required return self set some static struct
        subscript super switch throw throws true try typealias
        unowned var weak where while willSet
      )),
      types: MapSet.new(~w(
        Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64
        Float Double CGFloat Bool String Character Data Date URL
        Array Dictionary Set Optional Any AnyObject Error Result
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "===",
          "!==",
          "<=",
          ">=",
          "??",
          "...",
          "..<",
          "~>",
          "->",
          "&",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "&&",
          "||",
          "?",
          ":",
          "=",
          "."
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
