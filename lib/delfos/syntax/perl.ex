defmodule Delfos.Syntax.Perl do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Perl",
      line_comment: "#",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: false},
        %{delim: ~r/`/, end: ~r/`/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        my our local sub package use require no if elsif else unless
        given when default while for foreach do until continue last
        next redo goto return die warn say print open close eval
        bless ref tie untie defined undef exists delete scalar push
        pop shift unshift splice keys values each map grep sort
        reverse join split pack unpack
      )),
      types: MapSet.new(~w(
        SCALAR ARRAY HASH CODE REF GLOB FORMAT IO
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "<=>",
          "eq",
          "ne",
          "lt",
          "gt",
          "le",
          "ge",
          "cmp",
          "=~",
          "!~",
          "=>",
          "->",
          "++",
          "--",
          "**",
          "&&",
          "||",
          "//",
          "..",
          "...",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          ".=",
          "x",
          "=",
          "<>",
          "++",
          "--"
        ]),
      specials: [
        %Special{pattern: ~r/\$\w+/, type: :variable, priority: 10},
        %Special{pattern: ~r/@\w+/, type: :variable, priority: 10},
        %Special{pattern: ~r/%\w+/, type: :variable, priority: 10}
      ],
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
