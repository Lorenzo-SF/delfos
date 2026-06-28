defmodule Delfos.Syntax.Ada do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Ada",
      line_comment: "--",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/#?\d[\d_.]*(#[0-9A-Fa-f.]+#)?/,
      keywords: MapSet.new(~w(
        abort abs abstract accept access aliased all and
        array at begin body case constant declare delay
        delta digits do else elsif end entry exception exit
        for function generic goto if in interface is limited
        loop mod new not null of or others out overriding
        package pragma private procedure protected raise
        range record rem renames requeue return reverse
        select separate some subtype synchronized tagged
        task terminate then type until use when while with xor
      )),
      types: MapSet.new(~w(
        Integer Float Character Boolean String Natural Positive
        Long_Integer Long_Float Short_Integer Short_Float
        Duration Wide_Character Wide_String Unbounded_String
      )),
      operators:
        MapSet.new([
          "=",
          "/=",
          "<",
          "<=",
          ">",
          ">=",
          "=>",
          "..",
          ":=",
          ":",
          "+",
          "-",
          "*",
          "/",
          "**",
          "mod",
          "rem",
          "abs",
          "not",
          "and",
          "or",
          "xor",
          "&",
          "<>"
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
