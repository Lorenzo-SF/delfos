defmodule Delfos.Syntax.Css do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "CSS",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number:
        ~r/\b\d[\d_.]*(px|em|rem|%|vh|vw|vmin|vmax|pt|pc|in|cm|mm|ch|ex|deg|rad|grad|turn|s|ms|Hz|kHz|dpi|dpcm|dppx)?\b/,
      keywords: MapSet.new(~w(
        @import @media @keyframes @font-face @supports @namespace
        @page @charset @document @layer @container @scope
      )),
      types: MapSet.new(),
      operators:
        MapSet.new([
          ":",
          ";",
          ",",
          ">",
          "+",
          "~",
          "#",
          ".",
          "[",
          "]",
          "(",
          ")",
          "{",
          "}"
        ]),
      specials: [
        %Special{pattern: ~r/\.[a-zA-Z-]+/, type: :type, priority: 10},
        %Special{pattern: ~r/#[a-zA-Z-]+/, type: :decorator, priority: 10},
        %Special{pattern: ~r/@[a-zA-Z-]+/, type: :keyword, priority: 5},
        %Special{pattern: ~r/\b([a-zA-Z-]+)\s*:/, type: :builtin, priority: 15}
      ],
      module_separator: "",
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
