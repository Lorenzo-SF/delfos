defmodule Delfos.Syntax.Rust do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Rust",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/r"/, end: ~r/"/, escape: false},
        %{delim: ~r/r#"/, end: ~r/"/, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f\d+|u\d+|i\d+)?\b/,
      keywords: MapSet.new(~w(
        as async await break const continue crate dyn else enum
        extern false fn for if impl in let loop match mod move
        mut pub ref return self Self static struct super trait
        true type unsafe use where while yield
      )),
      types: MapSet.new(~w(
        bool char f32 f64 i8 i16 i32 i64 i128 isize
        u8 u16 u32 u64 u128 usize String Vec Box Option
        Result HashMap HashSet BTreeMap BTreeSet
        Arc Mutex RwLock Cow Cell RefCell
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "::",
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
          "&",
          "|",
          "^",
          "~",
          "!",
          "?"
        ]),
      specials: [
        %Special{pattern: ~r/'[a-z_]\w*/, type: :lifetime, priority: 10},
        %Special{pattern: ~r/\w+!/, type: :macro, priority: 20}
      ],
      module_separator: "::",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        macro: {:magenta, [:bold]},
        lifetime: {:cyan, [:italic]},
        operator: {:white, []},
        plain: {:white, []}
      }
    }
  end
end
