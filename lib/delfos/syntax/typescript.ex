defmodule Delfos.Syntax.TypeScript do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "TypeScript",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/`/, end: ~r/`/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(n|f|l|u)?\b/,
      keywords: MapSet.new(~w(
        async await break case catch class const continue debugger
        default delete do else enum export extends finally for
        function if import in instanceof let new of return static
        super switch this throw try typeof var void while with
        yield interface type implements abstract private protected
        public readonly declare namespace module
      )),
      types: MapSet.new(~w(
        string number boolean void never any unknown null undefined
        object Array Record Partial Pick Omit Exclude Extract
        Promise Map Set WeakMap WeakSet symbol bigint
      )),
      operators:
        MapSet.new([
          "===",
          "!==",
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "->",
          "++",
          "--",
          "**",
          "<<",
          ">>",
          "&&",
          "||",
          "??",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "&",
          "|",
          "^",
          "~",
          "?",
          ":",
          "."
        ]),
      specials: [
        %Special{pattern: ~r/@\w+(\.\w+)*/, type: :decorator, priority: 10},
        %Special{pattern: ~r/<\/?\w+[^>]*>/, type: :plain, priority: 20}
      ],
      module_separator: ".",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        decorator: {:yellow, []},
        operator: {:white, []},
        plain: {:white, []}
      }
    }
  end
end
