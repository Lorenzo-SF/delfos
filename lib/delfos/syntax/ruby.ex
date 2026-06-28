defmodule Delfos.Syntax.Ruby do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Ruby",
      line_comment: "#",
      block_comment: %{start: "=begin", end: "=end"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: false},
        %{delim: ~r/`/, end: ~r/`/, escape: true},
        %{delim: ~r/%q\(/, end: ~r/\)/, escape: false},
        %{delim: ~r/%Q\(/, end: ~r/\)/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(r|i)?\b/,
      keywords: MapSet.new(~w(
        BEGIN END alias begin break case class def defined? do
        else elsif end ensure false for if in module next nil
        not or redo rescue retry return self super then true
        undef unless until when while yield
      )),
      types: MapSet.new(~w(
        Array Hash String Integer Float Symbol Regexp
        Range Enumerator Time Date DateTime
        Proc Lambda Exception StandardError RuntimeError
        Module Class Object BasicObject NilClass TrueClass FalseClass
      )),
      operators:
        MapSet.new([
          "==",
          "===",
          "!=",
          "<=>",
          "<=",
          ">=",
          "=>",
          "->",
          "++",
          "--",
          "**",
          "<<",
          ">>",
          "&&",
          "||",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "..",
          "...",
          "&",
          "|",
          "^",
          "~",
          "!",
          "<=>"
        ]),
      specials: [
        %Special{pattern: ~r/\$\w+/, type: :variable, priority: 10},
        %Special{pattern: ~r/@@\w+/, type: :variable, priority: 10},
        %Special{pattern: ~r/@\w+/, type: :variable, priority: 11},
        %Special{pattern: ~r/:\w+[?!]?/, type: :atom, priority: 20},
        %Special{pattern: ~r/:\"[^\"]*\"/, type: :atom, priority: 20}
      ],
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        variable: {:red, []},
        atom: {:yellow, []},
        operator: {:white, []},
        plain: {:white, []}
      }
    }
  end
end
