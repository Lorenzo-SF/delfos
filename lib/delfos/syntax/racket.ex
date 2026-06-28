defmodule Delfos.Syntax.Racket do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Racket",
      line_comment: ";",
      block_comment: %{start: "#|", end: "|#"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      keywords: MapSet.new(~w(
        define define-syntax define-macro lambda λ let let*
        letrec let-values let*-values letrec-values if cond
        else case and or when unless begin begin0 begin-for-syntax
        do delay force quote quasiquote unquote unquote-splicing
        syntax syntax-rules syntax-case with-syntax
        provide require all-defined-out all-from-out
        rename-in except-in prefix-in only-in
        for for/list for/vector for/hash for/and for/or
        for/sum for/product for/fold
        for*/list for*/vector for*/hash for*/and for*/or
        for*/sum for*/product for*/fold
        match define/contract struct class interface mixin
        object new send inherit field super init
      )),
      types: MapSet.new(~w(
        number integer exact-integer rational float complex
        boolean char string symbol keyword pair list empty
        void eof null
      )),
      operators:
        MapSet.new([
          "=",
          "<",
          ">",
          "<=",
          ">=",
          "+",
          "-",
          "*",
          "/",
          "modulo",
          "quotient",
          "remainder",
          "cons",
          "car",
          "cdr",
          "list-ref",
          "append",
          "reverse",
          "length",
          "map",
          "filter",
          "foldl",
          "foldr",
          "apply",
          "compose",
          "andmap",
          "ormap",
          "memq",
          "memv",
          "member",
          "assq",
          "assv",
          "assoc",
          "eq?",
          "eqv?",
          "equal?",
          "string=?",
          "string<?",
          "symbol->string",
          "string->symbol",
          "number->string",
          "string->number",
          "format",
          "printf",
          ".",
          "=>",
          "...",
          "->",
          "set!"
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
