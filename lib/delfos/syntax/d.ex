defmodule Delfos.Syntax.D do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "D",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/q"/, end: ~r/"/, multiline: true, escape: false},
        %{delim: ~r/r"/, end: ~r/"/, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true},
        %{delim: ~r/`/, end: ~r/`/, escape: false}
      ],
      keywords: MapSet.new(~w(
        abstract alias align asm assert auto body bool break
        byte case cast catch char class const continue dchar
        debug default delegate delete deprecated do double
        else enum export extern false final finally float for
        foreach foreach_reverse function goto if import in
        inout int interface invariant is lazy long macro mixin
        module new nothrow null out override package pragma
        private protected public real ref return scope shared
        short static struct super switch synchronized template
        this throw true try typeid typeof ubyte ucent uint
        ulong union unittest ushort version void volatile wchar while with
      )),
      types: MapSet.new(~w(
        int long short byte ubyte uint ulong ushort
        float double real char wchar dchar bool string void
        size_t ptrdiff_t object Enum Struct Union Class
        Interface Array AssociativeArray Function Delegate TypeInfo
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "!<>",
          "!<>=<",
          "<",
          ">",
          "<=",
          ">=",
          "!<",
          "!>",
          "!<=",
          "!>=",
          "<>",
          "<>=",
          "is",
          "!is",
          "in",
          "!in",
          "..",
          "...",
          "=>",
          "->",
          "++",
          "--",
          "&&",
          "||",
          "&",
          "|",
          "^",
          "~",
          "<<",
          ">>",
          ">>>",
          "!",
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
          ">>>=",
          "~~",
          "~="
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
