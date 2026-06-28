defmodule Delfos.Syntax.Php do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "PHP",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|F|L)?\b/,
      keywords: MapSet.new(~w(
        abstract and array as break callable case catch class clone
        const continue declare default die do echo else elseif empty
        enddeclare endfor endforeach endif endswitch endwhile eval
        exit extends final finally fn for foreach function global
        goto if implements include include_once instanceof insteadof
        interface isset list match namespace new or print private
        protected public readonly require require_once return static
        switch throw trait try unset use var while xor yield
      )),
      types: MapSet.new(~w(
        int float bool string array object callable iterable void
        never mixed null resource self parent static false true
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
          "++",
          "--",
          "**",
          "<<",
          ">>",
          "&&",
          "||",
          "??",
          "...",
          "->",
          "::",
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
          "??=",
          ".=",
          "?->",
          "|",
          "&",
          "^",
          "~"
        ]),
      specials: [
        %Special{pattern: ~r/@\w+/, type: :decorator, priority: 10}
      ],
      module_separator: "\\",
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
