defmodule Delfos.Syntax.Groovy do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Groovy",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, escape: true, multiline: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true},
        %{delim: ~r/'''/, end: ~r/'''/, escape: true, multiline: true},
        %{delim: ~r/\$"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b0[xX][\da-fA-F]+|\b\d[\d_]*(\.\d+)?[gGdDfF]?\b/,
      keywords: MapSet.new(~w(
        abstract assert break case catch class const continue default do
        else enum extends false final finally for goto if implements import
        in instanceof interface native new null package private protected
        public return static strictfp super switch synchronized this throw
        throws transient true try void volatile while as def in trait mixin
      )),
      types: MapSet.new(~w(
        int long short byte char float double boolean String Object void
        List Map Set Range Closure Class GString Expando
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "<=>",
          "===",
          "!==",
          "=>",
          "..",
          "..<",
          "*.",
          "?.",
          "?:",
          "?.@",
          "?.&",
          "?.()",
          "*.",
          "*",
          "+",
          "-",
          "/",
          "%",
          "**",
          "++",
          "--",
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
          "&&",
          "||",
          "!",
          "&",
          "|",
          "^",
          "~",
          "<<",
          ">>",
          ">>>",
          "=~"
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
