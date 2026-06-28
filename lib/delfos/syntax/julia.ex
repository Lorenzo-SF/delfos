defmodule Delfos.Syntax.Julia do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Julia",
      line_comment: "#",
      block_comment: %{start: "#=", end: "=#"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f\d+|im|[box])?\b/,
      keywords: MapSet.new(~w(
        begin end function if else elseif for while do
        try catch finally return break continue
        mutable struct immutable struct abstract type primitive type
        module baremodule import export using include
        macro quote let local global const where
        true false nothing missing
      )),
      types: MapSet.new(~w(
        Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64
        Float16 Float32 Float64 BigInt BigFloat
        Complex String Char Bool Symbol
        Array Vector Matrix Tuple NamedTuple Set Dict Pair
        Union Any Nothing Number Integer AbstractFloat
        AbstractArray AbstractString
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "===",
          "!==",
          "<=",
          ">=",
          "=>",
          "<:",
          ">:",
          "::",
          "..",
          ".+",
          ".-",
          ".*",
          "./",
          ".^",
          ".//",
          "...",
          "-->",
          "//",
          "+=",
          "-=",
          "*=",
          "/=",
          "^=",
          "%=",
          "÷",
          "%",
          "&&",
          "||",
          "|",
          "&",
          "!",
          "~",
          "|>",
          "<|",
          "⊔",
          "∘"
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
