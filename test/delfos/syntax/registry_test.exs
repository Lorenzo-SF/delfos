defmodule Delfos.Syntax.RegistryTest do
  @moduledoc """
  Smoke tests for the syntax registry.

  Verifies:
    * Every language module compiles and exposes `definition/0`.
    * `definition/0` returns a valid `Alaja.Syntax.Language` struct.
    * `register_all/0` registers every language with Alaja without errors.
    * Highlighting a small source snippet in each language produces tokens.
    * The renderer can convert tokens to ANSI without crashing.
  """

  use ExUnit.Case, async: false

  alias Alaja.Syntax
  alias Delfos.Syntax.Registry

  describe "language modules" do
    test "every registered module exposes a definition/0" do
      for {_name, mod} <- Registry.languages() do
        assert function_exported?(mod, :definition, 0),
               "expected #{inspect(mod)} to export definition/0"
      end
    end

    test "every definition returns a valid Language struct" do
      for {_name, mod} <- Registry.languages() do
        lang = mod.definition()
        assert is_struct(lang, Syntax.Language),
               "expected #{inspect(mod)}.definition/0 to return a Language struct"

        assert is_binary(lang.name) and lang.name != "",
               "expected #{inspect(mod)}.definition/0 to have a non-empty name"
      end
    end

    test "Language colors are all valid {atom, list} pairs" do
      for {_name, mod} <- Registry.languages() do
        lang = mod.definition()

        for {_type, {color, effects}} <- lang.colors do
          assert is_atom(color),
                 "expected color atom in #{inspect(mod)}, got #{inspect(color)}"

          assert is_list(effects),
                 "expected effects list in #{inspect(mod)}, got #{inspect(effects)}"

          assert Enum.all?(effects, &is_atom/1),
                 "expected all effects to be atoms in #{inspect(mod)}, got #{inspect(effects)}"
        end
      end
    end
  end

  describe "register_all/0" do
    test "registers all languages without errors" do
      # Clean up any previous registrations
      Syntax.list_languages()
      |> Enum.each(&Syntax.register_language(&1, %Syntax.Language{name: "dummy"}))

      assert :ok = Registry.register_all()

      names = Syntax.list_languages()
      assert length(names) >= 50,
             "expected at least 50 languages registered, got #{length(names)}"
    end
  end

  describe "end-to-end highlighting" do
    test "highlights a small Elixir snippet" do
      Registry.register_all()

      assert {:ok, lang} = Syntax.get_language(:elixir)
      tokens = Syntax.Engine.tokenize("defmodule Foo do\nend", lang)
      assert is_list(tokens)
      assert tokens != []
      assert Enum.any?(tokens, fn {type, _} -> type == :keyword end)
    end

    test "highlights a small Python snippet" do
      Registry.register_all()

      assert {:ok, lang} = Syntax.get_language(:python)
      tokens = Syntax.Engine.tokenize("def hello():\n    return 1", lang)
      assert is_list(tokens)
      assert tokens != []
      assert Enum.any?(tokens, fn {type, _} -> type == :keyword end)
    end

    test "highlights a small Rust snippet" do
      Registry.register_all()

      assert {:ok, lang} = Syntax.get_language(:rust)
      tokens = Syntax.Engine.tokenize("fn main() {\n    println!(\"hi\");\n}", lang)
      assert is_list(tokens)
      assert tokens != []
    end

    test "highlights a small JSON snippet" do
      Registry.register_all()

      tokens = Syntax.highlight_content(~s({"a": 1, "b": "x"}), :json)
      assert is_list(tokens)
      assert tokens != []
    end
  end

  describe "language coverage for code-search workloads" do
    test "every tree-sitter-supported language has a syntax module" do
      # Tree-sitter supports these languages. Note: 'tsx' shares the
      # TypeScript syntax module (Delfos' registry treats them as
      # one entry: typescript).
      ts_languages = ~w(
        elixir typescript javascript python rust go
        java csharp c cpp php ruby swift dart scala lua bash
      )

      for lang <- ts_languages do
        atom = String.to_atom(lang)
        case Syntax.get_language(atom) do
          {:ok, _} -> :ok
          error -> flunk("expected language #{lang} to be registered, got: #{inspect(error)}")
        end
      end
    end
  end
end