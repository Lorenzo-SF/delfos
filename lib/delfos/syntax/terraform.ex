defmodule Delfos.Syntax.Terraform do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Terraform",
      line_comment: "#",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        resource data variable output provider module terraform locals backend
        provisioner connection lifecycle count depends_on source version
        required_providers required_version for_each each toset tolist tomap
        tostring tonumber format length merge lookup element concat keys values
        flatten indent jsonencode yamlencode file templatefile true false null
      )),
      types: MapSet.new(~w(
        string number bool list map object any set tuple dynamic
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "<<",
          ">>",
          "&&",
          "||",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "..",
          "?",
          ":",
          "=",
          "*",
          "+",
          "-",
          "<",
          ">",
          "!"
        ]),
      specials: [
        %Special{pattern: ~r/\$\{/, type: :keyword, priority: 5}
      ],
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
