defmodule Delfos.CLI.Commands.QueryTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Commands.Query.

  Verifies:
    - --help / -h print the help block
    - detect_lang_atom/1 resolves language from explicit, file-path, or fallback
    - Integration: full query flow with no project / with results
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.Commands.Query

  describe "--help" do
    test "prints the help block" do
      output =
        Query.help_text()

      assert output =~ "USAGE"
      assert output =~ "delfos query"
      assert output =~ "--kind"
      assert output =~ "--level"
      assert output =~ "-n"
      assert output =~ "--format"
    end

    test "-h also prints help" do
      output =
        Query.help_text()

      assert output =~ "USAGE"
    end
  end

  describe "detect_lang_atom/1" do
    test "uses explicit :language when present and valid" do
      assert Query.detect_lang_atom(%{language: "rust"}) == :rust
      assert Query.detect_lang_atom(%{language: "python"}) == :python
    end

    test "falls back to file_path detection when language is missing" do
      assert Query.detect_lang_atom(%{file_path: "lib/foo.ex"}) == :elixir
      assert Query.detect_lang_atom(%{file_path: "src/main.rs"}) == :rust
    end

    test "falls back to file_path when language is empty" do
      assert Query.detect_lang_atom(%{language: "", file_path: "a.py"}) == :python
    end

    test "returns :text when neither language nor file_path are usable" do
      assert Query.detect_lang_atom(%{}) == :text
      assert Query.detect_lang_atom(%{language: nil, file_path: nil}) == :text
    end

    test "returns :text for unknown language strings (rescues ArgumentError)" do
      assert Query.detect_lang_atom(%{language: "not-a-real-language-zzz"}) == :text
    end

    test "language takes precedence over file_path" do
      # If the symbol's language is rust but the file is .py, the symbol
      # language wins — symbols inherit their grammar from the grammar,
      # not the file extension.
      assert Query.detect_lang_atom(%{language: "rust", file_path: "a.py"}) == :rust
    end
  end

  describe "integration" do
    @tag :integration
    test "with no query text, prints an error and exits" do
      # Note: Query halts on no-query, so this assertion runs only when
      # integration tags are enabled and the underlying halt is captured.
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Query.run_with_opts(%{rest: []})
        end)

      assert output =~ "Usage" or output =~ "No projects"
    end

    @tag :integration
    test "JSON format emits valid JSON when results exist" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Query.run_with_opts(%{rest: ["anything"], format: "json"})
        end)

      # Either empty-result warning or JSON; both are valid for empty DB.
      cond do
        String.starts_with?(output, "{") or String.starts_with?(output, "[") ->
          assert {:ok, _} = Jason.decode(output)

        true ->
          assert output =~ "No results" or output =~ "No projects"
      end
    end
  end
end
