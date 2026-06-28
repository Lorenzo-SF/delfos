defmodule Delfos.Syntax.Makefile do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Makefile",
      line_comment: "#",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        ifeq ifneq ifdef ifndef else endif define endef
        override export private include -include vpath
      )),
      types: MapSet.new(),
      operators:
        MapSet.new([
          ":=",
          "=",
          "?=",
          "+=",
          "::",
          ":",
          ";",
          "|"
        ]),
      specials: [
        %Special{pattern: ~r/^\w+:?/, type: :keyword, priority: 10},
        %Special{pattern: ~r/\$\{?\w+\}?/, type: :variable, priority: 10},
        %Special{pattern: ~r/\$\$/, type: :variable, priority: 10}
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
