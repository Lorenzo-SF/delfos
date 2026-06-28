defmodule Delfos.Syntax.Fortran do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Fortran",
      line_comment: "!",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(d[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        program subroutine function module end do while if
        else elseif then forall where elsewhere continue stop
        return call allocate deallocate implicit none private
        public protected save intent in out inout optional
        pointer target allocatable dimension parameter data
        block interface contains external intrinsic sequence
        elemental pure recursive module procedure
      )),
      types: MapSet.new(~w(
        integer real double precision complex logical character
        dimension parameter common save external intrinsic
        intent optional pointer target allocatable byte
      )),
      operators:
        MapSet.new([
          "==",
          "/=",
          "<=",
          ">=",
          "//",
          "=>",
          "**",
          "+",
          "-",
          "*",
          "/",
          "<",
          ">",
          "<=",
          ">=",
          "==",
          "/=",
          ".and.",
          ".or.",
          ".not.",
          ".eqv.",
          ".neqv.",
          ".true.",
          ".false.",
          ".eq.",
          ".ne.",
          ".lt.",
          ".le.",
          ".gt.",
          ".ge."
        ]),
      specials: [],
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
