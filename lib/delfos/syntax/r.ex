defmodule Delfos.Syntax.R do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "R",
      line_comment: "#",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(L|i)?\b/,
      keywords: MapSet.new(~w(
        if else repeat while function for in next break return
        TRUE FALSE NULL Inf NaN NA NA_integer_ NA_real_
        NA_complex_ NA_character_
        switch try catch finally stop warning
        require library source setMethod setClass setGeneric
        setRefClass setValidity setAs slot new
      )),
      types: MapSet.new(~w(
        numeric integer logical character complex double raw
        list matrix array factor data.frame table environment
        expression pairlist language
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "<-",
          "<<-",
          "->",
          "->>",
          "%+%",
          "%-%",
          "%*%",
          "%%",
          "%/%",
          "%in%",
          ":::",
          "::",
          "$",
          "@",
          "&&",
          "||",
          "&",
          "|",
          "!",
          "~",
          "?"
        ]),
      specials: [],
      module_separator: "::",
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
