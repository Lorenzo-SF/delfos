defmodule Delfos.Syntax.Tex do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "TeX",
      line_comment: "%",
      block_comment: nil,
      strings: [],
      number: ~r/\b\d+(\.\d+)?\b/,
      keywords: MapSet.new(~w(
        documentclass usepackage begin end section subsection subsubsection
        chapter paragraph textbf textit texttt emph underline item enumerate
        itemize equation align figure table caption label ref cite maketitle
        author date title part includegraphics input include
        bibliographystyle bibliography newcommand renewcommand def let
        setlength bigskip medskip smallskip newpage linebreak pagebreak
        footnote
      )),
      types: MapSet.new([]),
      operators: MapSet.new(["⎨", "⎬", "[", "]", "_", "^", "&", "#", "$", "~", "%", "\\"]),
      specials: [
        %Special{
          pattern: ~r/\\[A-Za-z]+/,
          type: :keyword,
          priority: 5
        },
        %Special{
          pattern: ~r/\$\$?/,
          type: :builtin,
          priority: 10
        }
      ],
      module_separator: "",
      colors: %{
        keyword: {:blue, [:bold]},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        operator: {:white, []},
        builtin: {:cyan, []},
        plain: {:white, []}
      }
    }
  end
end
