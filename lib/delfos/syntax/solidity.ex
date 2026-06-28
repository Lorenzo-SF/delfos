defmodule Delfos.Syntax.Solidity do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Solidity",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        pragma solidity import contract library interface abstract is event
        enum struct modifier function returns return view pure payable nonpayable
        public private internal external constant immutable memory storage
        calldata indexed anonymous virtual override constructor fallback receive
        selfdestruct require revert assert emit mapping delete new for while
        do continue break if else try catch assembly unchecked using
      )),
      types: MapSet.new(~w(
        uint uint8 uint16 uint32 uint64 uint128 uint256
        int int8 int16 int32 int64 int128 int256
        address bool string bytes bytes1 bytes32 fixed ufixed address payable
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=>",
          "++",
          "--",
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
          "<<=",
          ">>=",
          "??",
          ":",
          "?",
          "=",
          "->",
          "::"
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
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
