defmodule Delfos.Syntax.Tcl do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Tcl",
      line_comment: "#",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(e[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        proc set list lappend lindex linsert lreplace lsearch lrange lsort
        lrepeat lreverse concat join split string append format scan regexp
        regsub subst upvar uplevel foreach while for if elseif else switch
        break continue return error catch throw trace after update vwait
        package namespace variable array dict source info rename interp
      )),
      types: MapSet.new([]),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "eq",
          "ne",
          "lt",
          "gt",
          "le",
          "ge",
          "in",
          "ni",
          "&&",
          "||",
          "!",
          "&",
          "|",
          "^",
          "~",
          "<<",
          ">>",
          "+",
          "-",
          "*",
          "/",
          "%",
          "**",
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
          "::",
          "?",
          ":",
          "="
        ]),
      specials: [
        %Special{
          pattern: ~r/\$\w+/,
          type: :variable,
          priority: 10
        }
      ],
      module_separator: "::",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
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
