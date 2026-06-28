defmodule Delfos.Syntax.PowerShell do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "PowerShell",
      line_comment: "#",
      block_comment: %{start: "<#", end: "#>"},
      strings: [
        %{delim: ~r/@"\n/, end: ~r/\n"@/, multiline: true, escape: true},
        %{delim: ~r/@'\n/, end: ~r/\n'@/, multiline: true, escape: false},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: false}
      ],
      number: ~r/\b\d[\d_.]*(l|d|f|m)?\b/,
      keywords: MapSet.new(~w(
        if elseif else switch for foreach foreach-object while
        do until continue break return function filter param
        begin process end in params trap throw try catch
        finally exit
        where where-object select select-object new-object
        write-output write-host write-error write-warning
        write-verbose write-debug
        import-module export-module module
        set-variable get-variable new-variable remove-variable
        add-type add-member get-command get-help get-member
        get-content set-content add-content clear-content
        get-child-item get-item set-item new-item remove-item
        rename-item move-item copy-item
        get-process stop-process start-sleep start-job wait-job
        get-job receive-job
      )),
      types: MapSet.new(~w(
        int long string char bool byte decimal float double
        DateTime Guid TimeSpan void object array hashtable
        psobject pscustomobject switch xml regex
      )),
      operators:
        MapSet.new([
          "-eq",
          "-ne",
          "-lt",
          "-le",
          "-gt",
          "-ge",
          "-like",
          "-notlike",
          "-match",
          "-notmatch",
          "-contains",
          "-notcontains",
          "-in",
          "-notin",
          "-is",
          "-isnot",
          "-as",
          "-and",
          "-or",
          "-xor",
          "-not",
          "-band",
          "-bor",
          "-bxor",
          "-bnot",
          "-shl",
          "-shr",
          "-replace",
          "-split",
          "-join",
          "..",
          "::",
          ".",
          "-&&",
          "-||",
          "%",
          "?",
          "?."
        ]),
      specials: [
        %Special{pattern: ~r/\$\w+/, type: :variable, priority: 10}
      ],
      module_separator: "\\",
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
