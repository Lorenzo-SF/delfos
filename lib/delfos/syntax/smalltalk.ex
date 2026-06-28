defmodule Delfos.Syntax.Smalltalk do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Smalltalk",
      line_comment: "\"",
      block_comment: nil,
      strings: [
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d+(\.\d+)?[se]?\b/,
      keywords: MapSet.new(~w(
        self super nil true false thisContext class new basicNew yourself
        yourself isNil notNil ifTrue ifFalse ifTrue ifFalse ifNil ifNotNil
        to by do whileTrue whileFalse timesRepeat repeat until assert should
        implement subclass class instanceVariable classInstanceVariable
        poolDictionary category method
      )),
      types: MapSet.new(~w(
        Object Number Integer Float Fraction Point Rectangle Color String
        Symbol Array OrderedCollection Set Dictionary ByteArray
        CompiledMethod Process BlockContext
      )),
      operators:
        MapSet.new([
          ":=",
          "^",
          ".",
          ";",
          ":",
          "=",
          "~=",
          "==",
          "~~",
          "|",
          "&",
          "->",
          "#",
          "@",
          "+",
          "-",
          "*",
          "/",
          "\\\\",
          "//",
          "=~",
          "~~",
          "~=",
          ">",
          "<",
          ">=",
          "<=",
          "=>",
          "|",
          "&",
          "?",
          "@"
        ]),
      specials: [
        %Special{
          pattern: ~r/#\w+/,
          type: :symbol,
          priority: 10
        }
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
