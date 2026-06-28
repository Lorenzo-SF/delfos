defmodule Delfos.Syntax.Nim do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Nim",
      line_comment: "#",
      block_comment: %{start: "#[", end: "]#"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        proc func method iterator template macro converter
        object type var let const result
        return if elif else case of when then
        for while break continue raise try except finally
        discard include import from export mixin bind
        using as block static defer asm bind to of
      )),
      types: MapSet.new(~w(
        int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64
        float float32 float64 bool char string cstring
        pointer array seq set tuple range openarray
        untyped typed varargs void any auto
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "->",
          "@",
          ":",
          "::",
          "$",
          "^",
          "..",
          "..<",
          "|>",
          "~",
          "and",
          "or",
          "not",
          "xor",
          "shl",
          "shr",
          "div",
          "mod",
          "in",
          "notin",
          "is",
          "isnot",
          "of",
          "as",
          "from",
          "..",
          "*",
          "/",
          "+",
          "-",
          "&",
          "|",
          "%",
          "<",
          ">",
          "=",
          "@",
          "~"
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
