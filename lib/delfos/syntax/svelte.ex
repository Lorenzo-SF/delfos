defmodule Delfos.Syntax.Svelte do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Svelte",
      line_comment: "//",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(e[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        let export import each if else await then catch html head slot window
        body document element script style lang
      )),
      types: MapSet.new([]),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "===",
          "!==",
          "&&",
          "||",
          "?",
          ":",
          ".",
          "|",
          "=",
          "+",
          "-",
          "*",
          "/",
          "%"
        ]),
      specials: [
        %Special{
          pattern: ~r/\{[\s\S]*?\}/,
          type: :variable,
          multiline: true,
          priority: 5
        },
        %Special{
          pattern: ~r/on:[\w]+/,
          type: :keyword,
          priority: 10
        },
        %Special{
          pattern: ~r/bind:[\w]+/,
          type: :keyword,
          priority: 10
        },
        %Special{
          pattern: ~r/use:[\w]+/,
          type: :keyword,
          priority: 10
        },
        %Special{
          pattern: ~r/class:[\w-]+/,
          type: :builtin,
          priority: 15
        }
      ],
      module_separator: ".",
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
