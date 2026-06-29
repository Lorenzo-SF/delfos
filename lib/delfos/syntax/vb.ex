defmodule Delfos.Syntax.Vb do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Visual Basic",
      line_comment: "'",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b\d[\d_]*(\.\d+)?([eE][+-]?\d+)?(#|%|&|@)?\b|&H[0-9a-fA-F]+|&O[0-7]+/,
      keywords: MapSet.new(~w(
        AddHandler AddressOf Alias And AndAlso As Boolean ByRef Byte
        ByVal Call Case Catch CBool CByte CChar CDate CDbl CDec Char
        CInt Class CLng CObj Const Continue CSByte CShort CSng CStr
        CType CUInt CULng CUShort Date Decimal Declare Default Delegate
        Dim DirectCast Do Double Each Else ElseIf End Enum Erase Error
        Event Exit False Finally For Friend Function Get GetType
        Global GoSub GoTo Handles If Implements Imports In Inherits
        Integer Interface Is IsNot Let Lib Like Long Loop Me Mod Module
        MustInherit MustOverride MyBase MyClass Namespace Narrowing New
        Next Not Nothing NotInheritable NotOverridable Object Of On
        Operator Option Optional Or OrElse Overloads Overridable Overrides
        ParamArray Partial Private Property Protected Public RaiseEvent
        ReadOnly ReDim RemoveHandler Resume Return SByte Select Set
        Shadows Shared Short Single Static Step Stop String Structure
        Sub SyncLock Then Throw To True Try TryCast TypeOf UInteger
        ULong UShort Using Variant Wend When While Widening With
        WithEvents WriteOnly Xor
      )),
      types: MapSet.new(~w(
        Integer Long Short Byte String Boolean Double Single Decimal
        Date Object Char Variant Currency
      )),
      operators:
        MapSet.new([
          "+",
          "-",
          "*",
          "/",
          "\\",
          "^",
          "Mod",
          "&",
          "=",
          "<>",
          "<",
          ">",
          "<=",
          ">=",
          "And",
          "Or",
          "Xor",
          "Not",
          "AndAlso",
          "OrElse",
          "Like",
          "Is",
          "IsNot"
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
