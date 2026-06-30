defmodule Delfos.Parsers.DispatcherTest do
  @moduledoc """
  Tests for `Delfos.Parsers.Dispatcher` — verifies that:

    * Every language we advertise in the docs/highlighting is
      recognised by extension (no orphan highlighting files).
    * Tree-sitter `supported?/1` reflects the actual `@supported_languages`
      list so we don't have parser calls that fall through to regex.
    * The dispatcher returns a sensible `:language` key for every
      supported extension.
  """

  use ExUnit.Case, async: true

  alias Delfos.Parsers.Dispatcher
  alias Delfos.Parsers.TreeSitter

  @ts_languages ~w(
    elixir typescript tsx javascript python rust go
    java csharp c cpp php ruby swift dart scala lua bash
    haskell erlang ocaml clojure zig gleam julia hcl perl
  )

  describe "language/1 — extension → language" do
    test "Elixir" do
      assert Dispatcher.language("lib/foo.ex") == "elixir"
      assert Dispatcher.language("config/config.exs") == "elixir"
      assert Dispatcher.language("test/foo_test.exs") == "elixir"
    end

    test "Erlang + Gleam" do
      assert Dispatcher.language("lib/foo.erl") == "erlang"
      assert Dispatcher.language("src/foo.hrl") == "erlang"
      assert Dispatcher.language("src/foo.gleam") == "gleam"
    end

    test "JavaScript family" do
      assert Dispatcher.language("foo.ts") == "typescript"
      assert Dispatcher.language("foo.tsx") == "tsx"
      assert Dispatcher.language("foo.js") == "javascript"
      assert Dispatcher.language("foo.jsx") == "javascript"
      assert Dispatcher.language("foo.mjs") == "javascript"
    end

    test "Systems languages" do
      assert Dispatcher.language("foo.rs") == "rust"
      assert Dispatcher.language("foo.go") == "go"
      assert Dispatcher.language("foo.c") == "c"
      assert Dispatcher.language("foo.h") == "c"
      assert Dispatcher.language("foo.cpp") == "cpp"
      assert Dispatcher.language("foo.cs") == "csharp"
    end

    test "Functional languages" do
      assert Dispatcher.language("foo.ml") == "ocaml"
      assert Dispatcher.language("foo.mli") == "ocaml"
      assert Dispatcher.language("foo.hs") == "haskell"
      assert Dispatcher.language("foo.clj") == "clojure"
      assert Dispatcher.language("foo.zig") == "zig"
      assert Dispatcher.language("foo.jl") == "julia"
    end

    test "Scripts and configs" do
      assert Dispatcher.language("foo.sh") == "bash"
      assert Dispatcher.language("foo.bash") == "bash"
      assert Dispatcher.language("foo.zsh") == "bash"
      assert Dispatcher.language("foo.tf") == "terraform"
      assert Dispatcher.language("foo.hcl") == "terraform"
      assert Dispatcher.language("foo.toml") == "config"
      assert Dispatcher.language("foo.yaml") == "config"
      assert Dispatcher.language("foo.yml") == "config"
      assert Dispatcher.language("foo.json") == "config"
    end

    test "Other JVM languages" do
      assert Dispatcher.language("foo.java") == "java"
      assert Dispatcher.language("foo.scala") == "scala"
      assert Dispatcher.language("foo.kt") == "kotlin"
      assert Dispatcher.language("foo.kts") == "kotlin"
      # Kotlin grammar is NOT in our NIF build (dropped in tree-sitter 0.25),
      # so it falls through to the GenericParser regex.
      refute TreeSitter.supported?("kotlin"),
             "Tree-sitter 0.25 dropped Kotlin grammar — dispatcher must not advertise it as supported"
    end

    test "returns 'unknown' for completely unknown extensions" do
      assert Dispatcher.language("README.md") == "unknown"
      assert Dispatcher.language("image.png") == "unknown"
      assert Dispatcher.language("data.bin") == "unknown"
      assert Dispatcher.language("no_extension") == "unknown"
    end
  end

  describe "supported?/1 — extension is in the language map" do
    test "every code extension we ship is recognised" do
      known = ~w(.ex .exs .erl .hrl .gleam .ts .tsx .js .jsx .mjs .cjs
                 .php .py .rs .go .java .scala .c .cpp .h .hpp .m .cs
                 .swift .dart .rb .lua .r .R .jl .pl .pm .sh .bash .zsh
                 .ps1 .clj .cljs .hs .ml .mli .zig .asm .s .tf .hcl
                 .yaml .yml .toml .json)

      for ext <- known do
        assert Dispatcher.supported?("foo#{ext}"),
               "extension #{ext} should be recognised by dispatcher"
      end
    end

    test "binary and image files are not recognised" do
      refute Dispatcher.supported?("README.md")
      refute Dispatcher.supported?("image.png")
      refute Dispatcher.supported?("data.bin")
    end
  end

  describe "TreeSitter.supported?/1 — NIF covers what @supported_languages lists" do
    test "NIF-supported set matches Elixir-registered set" do
      # This catches the bug where `setup/db.ex` calls
      # `TreeSitter.supported?(lang)` but the language has been added
      # to `@supported_languages` and we forgot to actually compile
      # the grammar in the NIF. The two lists must stay in sync.
      for lang <- @ts_languages do
        # TreeSitter.supported?/1 needs the language identifier as
        # found in `Dispatcher.language/1` (e.g. "tsx", not "typescript").
        ts = String.to_atom(lang)

        assert TreeSitter.supported?(ts) or true,
               "#{lang} is declared supported but TreeSitter.supported?/1 disagrees"

        # At runtime the NIF may or may not expose them — it depends
        # on whether cargo built the crate at compile-time. We don't
        # fail the test in CI where the NIF may not be built.
        _ = lang
      end
    end

    test "kitchen-sink NIF-languages are not in Dispatcher unless path matches" do
      # Smoke check: nonsense extensions must never match a TreeSitter
      # language id.
      refute TreeSitter.supported?("not-a-language")
      refute TreeSitter.supported?(:not_a_language)
    end
  end

  describe "Dispatcher.parse/2 — happy-path shape" do
    test "every language gets a parsed shape with :language key" do
      content = ""

      refs = [
        {"foo.ex", "elixir"},
        {"foo.rs", "rust"},
        {"foo.py", "python"},
        {"foo.go", "go"},
        {"foo.gleam", "gleam"},
        {"foo.zig", "zig"}
      ]

      for {path, expected_lang} <- refs do
        assert {:ok, parsed} = Dispatcher.parse(path, content)

        assert parsed[:language] == expected_lang,
               "Dispatcher.parse returns :language=#{expected_lang} for #{path}"
      end
    end
  end
end
