defmodule Delfos.Syntax.Crystal do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Crystal",
      line_comment: "#",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        abstract alias as asm begin break case class def
        do else elsif end ensure enum extend false for
        fun if in include instance_sizeof is_a? lib macro
        module next nil of out pointerof private protected
        property pub def rescue respond_to? return self
        sizeof struct super then true type typeof union
        unless until when while with yield
      )),
      types: MapSet.new(~w(
        Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64
        Float32 Float64 Bool Char String Symbol Nil
        Pointer Slice Array Hash Set Tuple NamedTuple
        Proc Union Enumerator Iterator Number Value Reference
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "<=>",
          "===",
          "=~",
          "!~",
          "=>",
          "->",
          "::",
          "..",
          "...",
          "||",
          "&&",
          "|=",
          "&=",
          "^=",
          "<=>",
          "**",
          "//",
          "%",
          "||",
          "&&",
          "|",
          "&",
          "^",
          "~",
          "<<",
          ">>",
          "+",
          "-",
          "*",
          "/",
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
          "||=",
          "&&=",
          "<=",
          ">=",
          "<",
          ">"
        ]),
      specials: [],
      module_separator: "::",
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
