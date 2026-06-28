defmodule Delfos.Syntax.Dart do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Dart",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/r"/, end: ~r/"/, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|F|L)?\b/,
      keywords: MapSet.new(~w(
        abstract as assert async await base break case catch class
        continue covariant default deferred do dynamic else enum
        export extends extension external factory false final finally
        for Function get hide if implements import in interface is
        late library mixin new null on operator out override part
        patch required rethrow return sealed set show static super
        switch sync this throw true try typedef var void while with
        yield
      )),
      types: MapSet.new(~w(
        int double num bool String List Set Map Record Symbol Object
        Type dynamic Never void Null Comparable Future Stream
        Iterable
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "??",
          "??=",
          "..",
          "?.",
          "?[]",
          "...",
          "...?",
          "~/",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "&=",
          "|=",
          "^=",
          "<<=",
          ">>=",
          "&&",
          "||",
          "?",
          ":",
          "=",
          "->"
        ]),
      specials: [
        %Special{pattern: ~r/@\w+/, type: :decorator, priority: 10}
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
        macro: {:magenta, [:bold]},
        plain: {:white, []}
      }
    }
  end
end
