defmodule Delfos.Syntax.Matlab do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "MATLAB",
      line_comment: "%",
      block_comment: %{start: "%{", end: "%}"},
      strings: [
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d+(\.\d+)?[eE][+-]?\d+|[+-]?\d+\.?\d*\b/,
      keywords: MapSet.new(~w(
        function if elseif else for while end return break continue switch
        case otherwise try catch error warning global persistent parfor spmd
        true false nan inf pi i j classdef properties methods events
        enumeration handle value abstract static public private protected
        sealed hidden constant dependent transient
      )),
      types: MapSet.new(~w(
        double single int8 int16 int32 int64 uint8 uint16 uint32 uint64
        logical char cell struct table categorical datetime duration
        calendarDuration function_handle
      )),
      operators:
        MapSet.new([
          "==",
          "~=",
          "<=",
          ">=",
          "&&",
          "||",
          "&",
          "|",
          "~",
          "<",
          ">",
          "=",
          "+",
          "-",
          "*",
          "/",
          ".*",
          "./",
          ".^",
          ".\\",
          "'",
          ".'",
          ":",
          ";",
          ",",
          "(",
          ")",
          "[",
          "]",
          "{",
          "}"
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
