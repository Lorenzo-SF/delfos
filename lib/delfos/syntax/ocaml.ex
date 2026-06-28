defmodule Delfos.Syntax.Ocaml do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "OCaml",
      line_comment: nil,
      block_comment: %{start: "(*", end: "*)"},
      strings: [
        %{delim: ~r/{|/, end: ~r/|}/, multiline: true, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(l|l32|l64|n)?\b/,
      keywords: MapSet.new(~w(
        and as assert asr begin class constraint do done
        downto else end exception external false for fun
        function functor if in include inherit initializer
        land lazy let lor lsl lsr lxor match method mod
        module mutable new nonrec object of open or private
        rec sig struct then to true try type val virtual
        when while with
      )),
      types: MapSet.new(~w(
        int float char string bool unit option list array
        bytes ref int32 int64 nativeint
      )),
      operators:
        MapSet.new([
          "!=",
          "<>",
          "<=",
          ">=",
          "::",
          "^",
          "@",
          "=>",
          "->",
          "<-",
          ":=",
          "=",
          "|>",
          ">>",
          ">>=",
          "||",
          "&&",
          "+",
          "-.",
          "+.",
          "*.",
          "/.",
          "mod",
          "land",
          "lor",
          "lxor",
          "lsl",
          "lsr",
          "asr",
          "**"
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
        macro: {:magenta, [:bold]},
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
