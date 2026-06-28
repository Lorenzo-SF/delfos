defmodule Delfos.Syntax.Bash do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Bash",
      line_comment: "#",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: false},
        %{delim: ~r/`/, end: ~r/`/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        if then else elif fi case esac for while do done
        until function in select return continue break exit
        declare local readonly export unset trap wait eval
        exec source set shift typeset unalias
        alias echo printf read cd pwd mkdir rm rmdir cp mv
        ln chmod chown grep sed awk sort uniq cut tr head
        tail wc cat less more find xargs kill ps top df du
        ping ssh scp curl wget tar gzip gunzip make
      )),
      types: MapSet.new(),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "=~",
          "&&",
          "||",
          ";;",
          ";",
          "&",
          "|",
          "<",
          ">",
          ">>",
          "<<<",
          "+=",
          "-=",
          "*=",
          "/=",
          "%=",
          "**",
          "||=",
          "&&=",
          "!=",
          "==",
          "-eq",
          "-ne",
          "-lt",
          "-le",
          "-gt",
          "-ge",
          "-nt",
          "-ot",
          "-ef",
          "-z",
          "-n",
          "-f",
          "-d",
          "-e",
          "-r",
          "-w",
          "-x",
          "-s",
          "-L",
          "-p",
          "-S",
          "-b",
          "-c",
          "-t",
          "-o",
          "-a",
          "-O",
          "-G",
          "-N"
        ]),
      specials: [
        %Special{pattern: ~r/\$\{?\w+\}?/, type: :variable, priority: 10},
        %Special{pattern: ~r/\$\w+/, type: :variable, priority: 10}
      ],
      module_separator: "",
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
