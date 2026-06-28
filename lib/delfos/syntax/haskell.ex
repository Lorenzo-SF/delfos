defmodule Delfos.Syntax.Haskell do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Haskell",
      line_comment: "--",
      block_comment: %{start: "{-", end: "-}"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        case class data default deriving do else family foreign
        if import in infix infixl infixr instance kind let
        module newtype of open pattern pragma qualified result
        role safe static type unsafe where deriving via
      )),
      types: MapSet.new(~w(
        Int Integer Float Double Bool Char String Ordering
        Maybe Either IO IOError Ratio Rational List Array
        Word Word8 Word16 Word32 Word64
      )),
      operators:
        MapSet.new([
          "==",
          "/=",
          "<=",
          ">=",
          "=>",
          "..",
          "::",
          "$",
          "$!",
          ".",
          "++",
          "!!",
          ">>",
          ">>=",
          "<-",
          "->",
          "=",
          "::",
          ":",
          ":~>",
          "<$>",
          "<*>",
          "<$",
          "<*",
          "*>",
          "<|>",
          "**",
          "&&",
          "||"
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
        macro: {:magenta, [:bold]},
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
