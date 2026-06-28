defmodule Delfos.Syntax.Pascal do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Pascal",
      line_comment: "//",
      block_comment: %{start: "{", end: "}"},
      strings: [
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\$\h+|\b\d[\d_.]*(e[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        program unit library function procedure constructor
        destructor class object interface implementation uses
        begin end if then else case of record array set file
        var const type label goto with while for do repeat
        until break continue exit raise try except finally at
        property read write stored default index name implements
        override overload virtual dynamic abstract sealed
        forward inline assembler external export public
        private protected published
      )),
      types: MapSet.new(~w(
        integer real double extended boolean char string
        shortint smallint longint byte word cardinal pointer
        text file array record set object class interface
      )),
      operators:
        MapSet.new([
          ":=",
          "=",
          "<>",
          "<",
          "<=",
          ">",
          ">=",
          "+",
          "-",
          "*",
          "/",
          "div",
          "mod",
          "not",
          "and",
          "or",
          "xor",
          "shl",
          "shr",
          "in",
          "..",
          "+=",
          "-=",
          "*=",
          "/="
        ]),
      specials: [],
      module_separator: ".",
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
