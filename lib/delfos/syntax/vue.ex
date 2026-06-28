defmodule Delfos.Syntax.Vue do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Vue",
      line_comment: "//",
      block_comment: %{start: "<!--", end: "-->"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(e[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        template script style scoped lang setup export default defineComponent
        props data computed methods watch mounted created updated
        beforeDestroy destroyed
      )),
      types: MapSet.new([]),
      operators:
        MapSet.new([
          "===",
          "!==",
          "==",
          "!=",
          "<=",
          ">=",
          "||",
          "&&",
          "??",
          "?.",
          ":",
          ".",
          "|",
          "?"
        ]),
      specials: [
        %Special{
          pattern: ~r/\{\{.*?\}\}/,
          type: :variable,
          multiline: false,
          priority: 5
        },
        %Special{
          pattern: ~r/v-[\w-]+/,
          type: :keyword,
          priority: 10
        },
        %Special{
          pattern: ~r/@\w+/,
          type: :decorator,
          priority: 10
        },
        %Special{
          pattern: ~r/:[\w-]+/,
          type: :builtin,
          priority: 10
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
