defmodule Delfos.Syntax.Toml do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "TOML",
      line_comment: "#",
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'''/, end: ~r/'''/, multiline: true, escape: false},
        %{delim: ~r/'/, end: ~r/'/, escape: false}
      ],
      number: ~r/\b\d[\d_.]*(e[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        true false
      )),
      types: MapSet.new([]),
      operators:
        MapSet.new([
          "=",
          "."
        ]),
      specials: [
        %Special{pattern: ~r/^\[[\w.]+\]/, type: :keyword, priority: 5},
        %Special{pattern: ~r/^\[\[[\w.]+\]\]/, type: :keyword, priority: 5}
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
