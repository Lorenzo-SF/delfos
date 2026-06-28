defmodule Delfos.Syntax.Clojure do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Clojure",
      line_comment: ";",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(M|N|bigint|float|double)?\b/,
      keywords: MapSet.new(~w(
        def defn defmacro defmethod defmulti defprotocol
        defrecord deftype defstruct defonce defproject
        let letfn if do when cond case for doseq dotimes
        while loop recur fn throw try catch finally
        quote ' ` , ~ #'
        ns in-ns require use import refer binding
        with-open with-local-vars with-out-str
      )),
      types: MapSet.new(~w(
        Integer Long Float Double Ratio BigInteger BigDecimal
        String Symbol Keyword Atom Ref Agent Var
        PersistentVector PersistentList PersistentHashMap
        PersistentHashSet PersistentArrayMap LazySeq
      )),
      operators:
        MapSet.new([
          "==",
          "=",
          "not=",
          "<",
          ">",
          "<=",
          ">=",
          "+",
          "-",
          "*",
          "/",
          "mod",
          "rem",
          "quot",
          "bit-and",
          "bit-or",
          "bit-xor",
          "bit-not",
          "bit-shift-left",
          "bit-shift-right",
          "inc",
          "dec",
          "max",
          "min",
          "comp",
          "partial",
          "complement",
          "juxt",
          "reduce",
          "map",
          "filter",
          "remove",
          "take",
          "drop",
          "first",
          "rest",
          "cons",
          "conj",
          "concat",
          "str"
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
