defmodule Delfos.Syntax.V do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "V",
      line_comment: "//",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        fn pub mut shared static volatile import module struct enum union
        type interface const global var mut for in if else match return or
        continue break goto as is typeof sizeof __offsetof print println
        panic error assert defer unsafe lock rlock spawn go select channel
        send receive atomic
      )),
      types: MapSet.new(~w(
        int i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool string byte rune
        void any map array chan thread
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "<-",
          "::",
          "..",
          "...",
          "++",
          "--",
          "&&",
          "||",
          "!",
          "&",
          "|",
          "^",
          "~",
          "<<",
          ">>",
          "+",
          "-",
          "*",
          "/",
          "%",
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
          "?",
          ":",
          "="
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
