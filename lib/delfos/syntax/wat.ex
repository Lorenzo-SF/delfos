defmodule Delfos.Syntax.Wat do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Wat",
      line_comment: ";;",
      block_comment: %{start: "(;", end: ";)"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b0x\h+|\b\d+(\.\d+)?\b/,
      keywords: MapSet.new(~w(
        module func start type param result local global memory table elem
        data export import mut null funcref externref ref drop select
        unreachable nop block loop if then else br br_if br_table call
        call_indirect return return_call return_call_indirect
      )),
      types: MapSet.new(~w(
        i32 i64 f32 f64 v128 externref funcref
      )),
      operators:
        MapSet.new([
          "(",
          ")",
          "=",
          "$",
          ".",
          ";"
        ]),
      specials: [
        %Special{pattern: ~r/\$\w+/, type: :variable, priority: 10}
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
