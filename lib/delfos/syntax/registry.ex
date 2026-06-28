defmodule Delfos.Syntax.Registry do
  @moduledoc """
  Registers all Delfos language definitions with Alaja's syntax system.

  Called once at application startup. Each definition is a
  `Alaja.Syntax.Language` struct stored in `:persistent_term`
  for fast read access during highlighting.
  """

  @doc "Registers all languages. Idempotent — safe to call multiple times."
  def register_all do
    for {name, module} <- languages() do
      Alaja.Syntax.register_language(name, module.definition())
    end

    :ok
  end

  @doc false
  def languages do
    [
      python: Delfos.Syntax.Python,
      typescript: Delfos.Syntax.TypeScript,
      rust: Delfos.Syntax.Rust,
      go: Delfos.Syntax.Go,
      java: Delfos.Syntax.Java,
      ruby: Delfos.Syntax.Ruby,
      elixir: Delfos.Syntax.Elixir,
      erlang: Delfos.Syntax.Erlang,
      javascript: Delfos.Syntax.JavaScript,
      c: Delfos.Syntax.C,
      cpp: Delfos.Syntax.Cpp,
      csharp: Delfos.Syntax.CSharp,
      kotlin: Delfos.Syntax.Kotlin,
      swift: Delfos.Syntax.Swift,
      scala: Delfos.Syntax.Scala,
      dart: Delfos.Syntax.Dart,
      php: Delfos.Syntax.Php,
      perl: Delfos.Syntax.Perl,
      r: Delfos.Syntax.R,
      julia: Delfos.Syntax.Julia,
      lua: Delfos.Syntax.Lua,
      haskell: Delfos.Syntax.Haskell,
      clojure: Delfos.Syntax.Clojure,
      ocaml: Delfos.Syntax.Ocaml,
      bash: Delfos.Syntax.Bash,
      powershell: Delfos.Syntax.PowerShell,
      sql: Delfos.Syntax.Sql,
      graphql: Delfos.Syntax.GraphQL,
      html: Delfos.Syntax.Html,
      css: Delfos.Syntax.Css,
      yaml: Delfos.Syntax.Yaml,
      toml: Delfos.Syntax.Toml,
      zig: Delfos.Syntax.Zig,
      nim: Delfos.Syntax.Nim,
      crystal: Delfos.Syntax.Crystal,
      dlang: Delfos.Syntax.D,
      fortran: Delfos.Syntax.Fortran,
      ada: Delfos.Syntax.Ada,
      pascal: Delfos.Syntax.Pascal,
      prolog: Delfos.Syntax.Prolog,
      racket: Delfos.Syntax.Racket,
      lisp: Delfos.Syntax.Lisp,
      solidity: Delfos.Syntax.Solidity,
      terraform: Delfos.Syntax.Terraform,
      dockerfile: Delfos.Syntax.Dockerfile,
      makefile: Delfos.Syntax.Makefile,
      gleam: Delfos.Syntax.Gleam,
      purescript: Delfos.Syntax.PureScript,
      hare: Delfos.Syntax.Hare,
      odin: Delfos.Syntax.Odin,
      vlang: Delfos.Syntax.V,
      wat: Delfos.Syntax.Wat,
      brainfuck: Delfos.Syntax.Brainfuck,
      coffeescript: Delfos.Syntax.CoffeeScript,
      xml: Delfos.Syntax.Xml,
      tex: Delfos.Syntax.Tex,
      matlab: Delfos.Syntax.Matlab,
      groovy: Delfos.Syntax.Groovy,
      gradle: Delfos.Syntax.Gradle,
      haxe: Delfos.Syntax.Haxe,
      smalltalk: Delfos.Syntax.Smalltalk,
      tcl: Delfos.Syntax.Tcl,
      objc: Delfos.Syntax.Objc,
      vue: Delfos.Syntax.Vue,
      svelte: Delfos.Syntax.Svelte,
      applescript: Delfos.Syntax.AppleScript
    ]
  end
end
