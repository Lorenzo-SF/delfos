defmodule Delfos.Syntax.UtilsTest do
  @moduledoc """
  Unit tests for Delfos.Syntax.Utils.

  Verifies:
    - safe_to_atom/1 converts known languages and falls back to :text
    - detect_lang_atom/1 follows language → file_path → :text fallback chain
  """

  use ExUnit.Case, async: false

  alias Delfos.Syntax.Utils

  describe "safe_to_atom/1" do
    test "converts a registered language string to its atom" do
      # Both :elixir (built-in to Alaja) and :rust (registered by Delfos
      # via Delfos.Syntax.Registry.register_all/0) must resolve.
      assert Utils.safe_to_atom("elixir") == :elixir
      assert Utils.safe_to_atom("rust") == :rust
      assert Utils.safe_to_atom("python") == :python
    end

    test "returns :text for an unregistered language string" do
      assert Utils.safe_to_atom("this-language-does-not-exist-zzz") == :text
    end

    test "returns :text for empty or nil input" do
      assert Utils.safe_to_atom("") == :text
      assert Utils.safe_to_atom(nil) == :text
    end

    test "returns :text for non-binary input" do
      assert Utils.safe_to_atom(42) == :text
      assert Utils.safe_to_atom(:rust) == :text
      assert Utils.safe_to_atom(%{}) == :text
    end
  end

  describe "detect_lang_atom/1" do
    test "uses explicit :language when present and valid" do
      assert Utils.detect_lang_atom(%{language: "rust"}) == :rust
      assert Utils.detect_lang_atom(%{language: "python"}) == :python
    end

    test "falls back to file_path detection when language is missing" do
      assert Utils.detect_lang_atom(%{file_path: "lib/foo.ex"}) == :elixir
      assert Utils.detect_lang_atom(%{file_path: "src/main.rs"}) == :rust
    end

    test "falls back to file_path when language is empty" do
      assert Utils.detect_lang_atom(%{language: "", file_path: "a.py"}) == :python
    end

    test "returns :text when neither language nor file_path are usable" do
      assert Utils.detect_lang_atom(%{}) == :text
      assert Utils.detect_lang_atom(%{language: nil, file_path: nil}) == :text
    end

    test "returns :text for unknown language strings (rescues ArgumentError)" do
      assert Utils.detect_lang_atom(%{language: "not-a-real-language-zzz"}) == :text
    end

    test "language takes precedence over file_path" do
      assert Utils.detect_lang_atom(%{language: "rust", file_path: "a.py"}) == :rust
    end

    test "returns :text for non-map input" do
      assert Utils.detect_lang_atom(nil) == :text
      assert Utils.detect_lang_atom("string") == :text
      assert Utils.detect_lang_atom(42) == :text
    end
  end
end
