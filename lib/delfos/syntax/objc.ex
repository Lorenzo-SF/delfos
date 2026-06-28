defmodule Delfos.Syntax.Objc do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Objective-C",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/@"/, end: ~r/"/, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(e[+-]?\d+)?[uUlLfF]?\b/,
      keywords: MapSet.new(~w(
        self super _cmd id nil Nil YES NO BOOL true false null return break
        continue if else for while do switch case default goto typeof
        interface implementation protocol property synthesize dynamic class
        selector encode synchronized try catch finally throw autoreleasepool
        public private protected package required optional
      )),
      types: MapSet.new(~w(
        int long long long short char float double void id BOOL SEL IMP
        Class NSString NSArray NSDictionary NSSet NSNumber NSDate NSData
        NSURL NSError NSException NSObject UIView UIViewController
        UIColor UIImage UILabel UITableView UICollectionView
      )),
      operators:
        MapSet.new([
          "==",
          "!=",
          "<=",
          ">=",
          "->",
          "::",
          "^",
          "^^",
          "||",
          "&&",
          "|=",
          "&=",
          "|=",
          "^=",
          "<<=",
          ">>=",
          "..",
          "...",
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
          ".",
          "->"
        ]),
      specials: [
        %Special{
          pattern: ~r/@\w+/,
          type: :decorator,
          priority: 5
        }
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
