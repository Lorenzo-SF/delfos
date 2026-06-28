defmodule Delfos.Syntax.Cpp do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "C++",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        alignas alignof auto bool break case catch char class
        concept const consteval constexpr constinit continue
        decltype default delete do double else enum explicit
        export extern false float for friend goto if inline int
        long mutable namespace new noexcept nullptr operator
        override private protected public register requires
        reinterpret_cast return short signed sizeof static
        static_assert static_cast struct switch template this
        throw true try typedef typeid typename union unsigned
        using virtual void volatile while
      )),
      types: MapSet.new(~w(
        int float double char bool void string vector map set
        unordered_map unordered_set shared_ptr unique_ptr
        weak_ptr pair tuple optional variant any int8_t int16_t
        int32_t int64_t uint8_t uint16_t uint32_t uint64_t
        size_t
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "++",
          "--",
          "->*",
          "->",
          "<<",
          ">>",
          "&&",
          "||",
          "::",
          "...",
          "<=>",
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
          "=",
          "->",
          "&",
          "|",
          "~"
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
        macro: {:magenta, [:bold]},
        plain: {:white, []}
      }
    }
  end
end
