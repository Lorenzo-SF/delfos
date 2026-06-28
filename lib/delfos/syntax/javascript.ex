defmodule Delfos.Syntax.JavaScript do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "JavaScript",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/`/, end: ~r/`/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        async await break case catch class const continue debugger
        default delete do else export extends finally for function
        if import in instanceof let new of return static super
        switch this throw try typeof var void while with yield
      )),
      types: MapSet.new(~w(
        string number boolean symbol null undefined object Array
        Map Set Promise WeakMap WeakSet Function Date RegExp Error
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
          "&&=",
          "||=",
          "??=",
          "..",
          "...",
          "?.",
          "?:",
          "=",
          "->"
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
