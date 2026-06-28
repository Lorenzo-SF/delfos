defmodule Delfos.Syntax.Odin do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Odin",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        proc struct enum union using package import when if else for
        switch case fallthrough defer return or_else or_return break
        continue foreign distinct where no_bounds_check
        optional_integer_overflow no_inline force_inline require_results
        require_export require_target_features require_endian
        require_os require_arch
      )),
      types: MapSet.new(~w(
        int i8 i16 i32 i64 u8 u16 u32 u64 uint f16 f32 f64
        bool string rune byte any rawptr typeid int128 u128
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "<-",
          "->",
          "::",
          "..",
          "..<",
          "...",
          "or",
          "and",
          "not",
          "&",
          "|",
          "~",
          "<<",
          ">>",
          "+",
          "-",
          "*",
          "/",
          "%",
          "||",
          "&&",
          "..",
          "|",
          "~"
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
