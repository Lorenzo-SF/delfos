defmodule Delfos.Syntax.Erlang do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Erlang",
      line_comment: "%",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        case catch cond fun if let of receive when and also or
        xor not after begin end export import module define
        include record type spec callback if case receive try
        catch throw
      )),
      types: MapSet.new(~w(
        integer float atom binary tuple list map pid port
        reference boolean string char number term any
      )),
      operators:
        MapSet.new([
          "=:=",
          "=/=",
          "==",
          "/=",
          "=<",
          ">=",
          ">",
          "<",
          "++",
          "--",
          "=",
          "!",
          "=>",
          "<-",
          ".."
        ]),
      specials: [
        %Special{pattern: ~r/-[a-z_]\w*(\([^)]*\))?/, type: :decorator, priority: 10}
      ],
      module_separator: ":",
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
