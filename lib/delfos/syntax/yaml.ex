defmodule Delfos.Syntax.Yaml do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "YAML",
      line_comment: "#",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: false}
      ],
      keywords: MapSet.new(~w(
        true false yes no on off null ~
        & * ! <<
      )),
      types: MapSet.new([]),
      operators:
        MapSet.new([
          ":",
          "-",
          ",",
          "&",
          "*",
          "!",
          ">",
          "|",
          "<<"
        ]),
      specials: [
        %Special{pattern: ~r/^---/, type: :keyword, priority: 5},
        %Special{pattern: ~r/^\.\.\./, type: :keyword, priority: 5}
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
