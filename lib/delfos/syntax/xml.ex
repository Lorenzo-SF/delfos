defmodule Delfos.Syntax.Xml do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "XML",
      line_comment: nil,
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: nil,
      keywords: MapSet.new([]),
      types: MapSet.new([]),
      operators: MapSet.new([]),
      specials: [
        %Special{
          pattern: ~r/<!--[\s\S]*?-->/,
          type: :comment,
          multiline: true,
          priority: 5
        },
        %Special{
          pattern: ~r/<\/?[\w:-]+[^>]*>/,
          type: :module,
          priority: 10
        },
        %Special{
          pattern: ~r/&[\w#]+;/,
          type: :builtin,
          priority: 15
        }
      ],
      module_separator: ":",
      colors: %{
        comment: {:bright_black, [:italic]},
        module: {:magenta, []},
        builtin: {:cyan, []},
        plain: {:white, []}
      }
    }
  end
end
