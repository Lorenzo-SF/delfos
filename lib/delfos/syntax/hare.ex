defmodule Delfos.Syntax.Hare do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Hare",
      line_comment: "//",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        fn let const def type struct union enum use export nullable
        void null true false if else match switch case yield for while
        break continue return abort assert static append delete insert
        alloc free len size offset strings
      )),
      types: MapSet.new(~w(
        int i8 i16 i32 i64 uint u8 u16 u32 u64 size char bool str
        f32 f64 void nullable null error tagged union struct enum
        fn pointer slice array
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "..",
          "=>",
          "->",
          "++",
          "--",
          "...",
          "&&",
          "||",
          "!",
          "&",
          "|",
          "^",
          "~",
          "<<",
          ">>",
          "*=",
          "/=",
          "%=",
          "+=",
          "-=",
          "&=",
          "|=",
          "^=",
          "<<=",
          ">>=",
          "??",
          ":",
          "?",
          "=",
          "*",
          "+",
          "-",
          "<",
          ">",
          ":"
        ]),
      specials: [],
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
