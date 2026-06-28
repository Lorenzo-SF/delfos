defmodule Delfos.Syntax.CSharp do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "C#",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/@"/, end: ~r/"/, multiline: true, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|d|l|m|F|D|L|M)?\b/,
      keywords: MapSet.new(~w(
        abstract as async await base bool break byte case catch
        char checked class const continue decimal default delegate
        do double else enum event explicit extern false finally
        fixed float for foreach get goto if implicit in init int
        interface internal is lock long namespace new null object
        operator out override params private protected public
        readonly ref record return sbyte sealed set short sizeof
        stackalloc static string struct switch this throw true try
        typeof uint ulong unchecked unsafe ushort using value
        virtual void volatile while yield
      )),
      types: MapSet.new(~w(
        int long float double char bool byte short string object
        void decimal DateTime TimeSpan Guid Task Task<T>
        IEnumerable IList List Dictionary KeyValuePair Nullable
        var dynamic nint nuint
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "++",
          "--",
          "&&",
          "||",
          "??",
          "??=",
          "=>",
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
          "::",
          "?",
          ":",
          "=",
          "->",
          "..",
          "."
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
