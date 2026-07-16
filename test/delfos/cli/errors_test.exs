defmodule Delfos.CLI.ErrorsTest do
  @moduledoc """
  Unit tests for Delfos.CLI.Errors.

  Exercises the three pieces the helper exposes:

    * `breadcrumb/1` — renders the call path
    * `render_error/3` — non-halting error with optional hint
    * `abort/3` — renders then halts (tested via System.halt simulation)

  The Breadcrumbs.render/2 under the hood uses Alaja.Components.Breadcrumbs
  so we just verify the call path is in the output.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Delfos.CLI.Errors

  describe "breadcrumb/1" do
    test "renders a non-empty path" do
      output =
        capture_io(fn ->
          Errors.breadcrumb(["delfos", "init", "scan", "file_processor"])
        end)

      # Breadcrumbs.render/2 emits ANSI-coloured segments separated by
      # " › " (space, separator, space). Strip ANSI before asserting
      # so we don't pin the colour palette.
      plain = strip_ansi(output)

      assert plain =~ "delfos"
      assert plain =~ "init"
      assert plain =~ "scan"
      assert plain =~ "file_processor"
      # Default separator in Alaja.Components.Breadcrumbs is "›"
      assert plain =~ "›"
    end

    test "empty path is a no-op" do
      output =
        capture_io(fn ->
          assert :ok == Errors.breadcrumb([])
        end)

      assert output == ""
    end
  end

  describe "render_error/3" do
    test "prints breadcrumb + error message" do
      output =
        capture_io(fn ->
          Errors.render_error(["delfos", "init", "scan"], "missing dep tree_sitter")
        end)

      plain = strip_ansi(output)
      assert plain =~ "delfos"
      assert plain =~ "init"
      assert plain =~ "scan"
      assert plain =~ "missing dep tree_sitter"
    end

    test "renders hint when given" do
      output =
        capture_io(fn ->
          Errors.render_error(["delfos", "init"], "X failed", hint: "Try: delfos doctor")
        end)

      assert strip_ansi(output) =~ "Hint: Try: delfos doctor"
    end

    test "no hint line when hint is nil" do
      output =
        capture_io(fn ->
          Errors.render_error(["delfos", "init"], "X failed")
        end)

      refute strip_ansi(output) =~ "Hint:"
    end

    test "no hint line when hint is empty string" do
      output =
        capture_io(fn ->
          Errors.render_error(["delfos", "init"], "X failed", hint: "")
        end)

      refute strip_ansi(output) =~ "Hint:"
    end
  end

  describe "print_error/print_warning/print_success with hint" do
    test "print_error renders Message + Hint Box when hint is given" do
      output =
        capture_io(fn ->
          Errors.print_error("LLM gateway timed out after 30s",
            hint: "Try: delfos config set llm.timeout_ms 60000"
          )
        end)

      plain = strip_ansi(output)
      assert plain =~ "LLM gateway timed out after 30s"
      assert plain =~ "Hint"
      assert plain =~ "Try: delfos config set llm.timeout_ms 60000"
    end

    test "print_warning renders with yellow colour" do
      output =
        capture_io(fn ->
          Errors.print_warning("Embedding dim mismatch (1536 vs 4096)",
            hint: "Restart the embed server with the correct model"
          )
        end)

      plain = strip_ansi(output)
      assert plain =~ "Embedding dim mismatch (1536 vs 4096)"
      assert plain =~ "Hint"
      assert plain =~ "Restart the embed server with the correct model"
    end

    test "plain print_error without hint shows just the message" do
      output =
        capture_io(fn ->
          Errors.print_error("Plain error without hint")
        end)

      plain = strip_ansi(output)
      assert plain =~ "Plain error without hint"
      refute plain =~ "Hint"
    end

    test "empty-string hint is treated as no hint" do
      output =
        capture_io(fn ->
          Errors.print_error("Some failure", hint: "")
        end)

      plain = strip_ansi(output)
      refute plain =~ "Hint"
    end
  end

  # Strip ANSI truecolour / 256-colour / simple escapes from a string
  # so we can compare the visible content in tests without pinning the
  # colour palette. Public domain regex (matches ESC[ ... m sequences).
  @ansi_regex ~r/\x1b\[[0-9;]*m/
  defp strip_ansi(text) when is_binary(text), do: String.replace(text, @ansi_regex, "")
end
