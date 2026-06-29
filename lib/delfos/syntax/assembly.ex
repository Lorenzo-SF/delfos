defmodule Delfos.Syntax.Assembly do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Assembly",
      line_comment: ";",
      block_comment: nil,
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b0[xX][0-9a-fA-F]+[hH]?|\b[01]+[bB]|\b\d[\d_]*\b/,
      keywords: MapSet.new(~w(
        mov push pop call ret jmp je jne jz jnz jg jl jge jle ja jb jae jbe
        add sub mul div inc dec and or xor not shl shr sal sar neg
        nop lea cmp test xchg movsx movzx cwde cdq cqo
        syscall int hlt cli sti in out
        section segment global extern
        db dw dd dq dt
        byte word dword qword ptr
        align org times
        equ macro endm include incbin
        .data .text .bss
      )),
      types: MapSet.new(~w(
        rax rbx rcx rdx rsi rdi rsp rbp rip
        eax ebx ecx edx esi edi esp ebp eip
        ax bx cx dx si di sp bp
        al ah bl bh cl ch dl dh
        r8 r9 r10 r11 r12 r13 r14 r15
        r8d r9d r10d r11d r12d r13d r14d r15d
        r8w r9w r10w r11w r12w r13w r14w r15w
        r8b r9b r10b r11b r12b r13b r14b r15b
        x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15
        r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12 r13 r14 r15
        lr sp pc
      )),
      operators:
        MapSet.new([
          "+",
          "-",
          "*",
          "/",
          "%",
          "<<",
          ">>",
          "&",
          "|",
          "^",
          "~",
          "==",
          "!=",
          "<",
          ">",
          "<=",
          ">=",
          "&&",
          "||",
          "!"
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
