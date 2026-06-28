defmodule Delfos.Syntax.Elixir do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Elixir",
      line_comment: "#",
      block_comment: nil,
      strings: [
        %{delim: ~r/"""/, end: ~r/"""/, multiline: true, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        def defp defmodule defmacro defguard defstruct do end
        case cond if else unless with when fn let try rescue
        catch after throw raise receive send import use alias
        require quote unquote super and or not in nil true false
      )),
      types: MapSet.new(~w(
        PID Reference Atom Map List Tuple Integer Float Function
        Port Module
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "===",
          "!==",
          "<=",
          ">=",
          "&&",
          "||",
          "<>",
          "++",
          "--",
          "|>",
          "=",
          "<-",
          "->",
          "|",
          "~>",
          "<~",
          "~>>",
          "<<~",
          "~>",
          "<~",
          "<|>",
          "<|",
          "||>",
          "|||>",
          "&&>",
          "&&&>",
          "=~",
          ".."
        ]),
      specials: [
        %Special{pattern: ~r/~[rRwWsdDcC](['"(\[]{1})/, type: :sigil, consume: true, priority: 5},
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
