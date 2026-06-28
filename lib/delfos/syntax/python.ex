defmodule Delfos.Syntax.Python do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Python",
      line_comment: "#",
      block_comment: %{start: ~s('''), end: ~s(''')},
      strings: [
        %{delim: ~r/f"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/f'/, end: ~r/'/, escape: true},
        %{delim: ~r/f"/, end: ~r/"/, escape: true},
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(e\d+)?[jJ]?\b/,
      keywords: MapSet.new(~w(
        False None True and as assert async await break class
        continue def del elif else except finally for from global
        if import in is lambda nonlocal not or pass raise return
        try while with yield
      )),
      types: MapSet.new(~w(
        int float str bool list dict tuple set frozenset
        bytes bytearray complex range map filter type
        Exception BaseException object
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "->",
          "**",
          "//",
          ":=",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "<<",
          ">>",
          "and",
          "or",
          "not",
          "is",
          "in"
        ]),
      specials: [
        %Special{pattern: ~r/@\w+(\.\w+)*/, type: :decorator, priority: 10}
      ],
      module_separator: ".",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        decorator: {:yellow, []},
        operator: {:white, []},
        builtin: {:cyan, []},
        plain: {:white, []}
      }
    }
  end
end
