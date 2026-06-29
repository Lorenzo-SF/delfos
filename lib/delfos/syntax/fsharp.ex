defmodule Delfos.Syntax.FSharp do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "F#",
      line_comment: "//",
      block_comment: %{start: "(*", end: "*)"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/@"/, end: ~r/"/, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: false}
      ],
      number: ~r/\b0[xX][0-9a-fA-F]+[uUlL]?|\b\d[\d_]*(\.\d+)?([eE][+-]?\d+)?[fFmM]?\b/,
      keywords: MapSet.new(~w(
        abstract and as assert base begin class default delegate do
        done downcast downto elif else end exception extern false
        finally fixed for fun function global if in inherit inline
        interface internal lazy let match member module mutable namespace
        new null of open or override private public rec return sig
        static struct then to true try type upcast use val void when
        while with yield
        async await
        not
      )),
      types: MapSet.new(~w(
        int long short byte sbyte uint ulong ushort single double
        decimal bool char string void obj unit bigint
        list array seq option result Choice Result
        Map Set Dictionary Queue Stack
      )),
      operators:
        MapSet.new([
          "+",
          "-",
          "*",
          "/",
          "%",
          "**",
          "<<",
          ">>",
          "&",
          "&&",
          "|",
          "||",
          "^",
          "=",
          "<>",
          "<",
          ">",
          "<=",
          ">=",
          ":=",
          "->",
          "<-",
          "|>",
          "<|",
          ">>",
          "<<",
          "||>",
          "<||",
          "..",
          "?",
          "!"
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
