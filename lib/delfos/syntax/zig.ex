defmodule Delfos.Syntax.Zig do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Zig",
      line_comment: "//",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        const var fn return if else switch for while break continue
        defer errdefer unreachable try catch async await suspend resume
        comptime compiletime export extern inline noinline nakedcc
        callconv volatile align linksection threadlocal usingnamespace
        pub struct enum union type packed error opaque anytype
        anyopaque undefined null true false and or not
      )),
      types: MapSet.new(~w(
        u8 u16 u32 u64 i8 i16 i32 i64 f16 f32 f64 f128
        isize usize bool void type anyerror anyopaque anytype
        comptime_int comptime_float
        c_short c_int c_long c_longlong c_uchar c_ushort
        c_uint c_ulong c_ulonglong
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "++",
          "**",
          ">>",
          "<<",
          "&",
          "|",
          "^",
          "~",
          "orelse",
          "catch",
          ".?",
          "..",
          "..=",
          "=>",
          "->",
          "%%",
          "|||",
          "&&&",
          "|=",
          "^=",
          "&=",
          "<<=",
          ">>=",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "||",
          ".",
          "?"
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
