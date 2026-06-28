defmodule Delfos.Syntax.Lisp do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Common Lisp",
      line_comment: ";",
      block_comment: %{start: "#|", end: "|#"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b[\d.]+(e[+-]?\d+)?[fdlsl]?\b/,
      keywords: MapSet.new(~w(
        defun defmacro defvar defparameter defconstant defstruct
        defclass defmethod defgeneric defpackage in-package
        use-package export import shadow shadowing-import
        unintern in-readtable let let* letf letf* flet labels
        macrolet if when unless cond case ecase typecase
        etypecase case t nil quote function setq setf psetq
        loop do do* dotimes dolist tagbody go prog prog*
        return return-from block catch throw handler-case
        handler-bind ignore-errors declare proclaim locally
        the check-type assert error warn break
      )),
      types: MapSet.new(~w(
        integer fixnum bignum ratio float short-float
        single-float double-float long-float complex
        character string symbol null cons list vector array
        hash-table package readtable stream pathname random-state
      )),
      operators:
        MapSet.new([
          "=",
          "/=",
          "<",
          ">",
          "<=",
          ">=",
          "+",
          "-",
          "*",
          "/",
          "1+",
          "1-",
          "incf",
          "decf",
          "mod",
          "rem",
          "floor",
          "ceiling",
          "truncate",
          "round",
          "expt",
          "sqrt",
          "sin",
          "cos",
          "tan",
          "asin",
          "acos",
          "atan",
          "log",
          "abs",
          "equal",
          "equalp",
          "eql",
          "eq",
          "string=",
          "char=",
          "not",
          "and",
          "or",
          "car",
          "cdr",
          "caar",
          "cadr",
          "cdar",
          "cddr",
          "cons",
          "list",
          "append",
          "reverse",
          "nth",
          "elt",
          "aref",
          "svref",
          "char",
          "length",
          "member",
          "assoc",
          "find",
          "remove",
          "delete",
          "substitute",
          "count",
          "mapcar",
          "mapcan",
          "mapc",
          "maplist",
          "mapl",
          "reduce",
          "some",
          "every",
          "notevery",
          "notany"
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
