defmodule Delfos.MCP.Tools.MetaprogramHintTest do
  @moduledoc """
  Unit tests for the metaprogram detection heuristic.

  Pre-v2.6.0 the callers/callees tools returned "sin callers"
  / "grafo incompleto" with no diagnostic when the function was
  metaprogram-generated. Bug #25 is NIF-side (full fix would
  require tracking `quote do` blocks at parse time). This is the
  pragmatic partial fix: detect macro-generated functions by
  scanning the source for the function name inside `quote do`
  blocks, then surface a Hint in the empty-result path.

  These tests exercise the internal `extract_quote_blocks/1` and
  `metaprogrammed?/2` helpers (both are defp but accessible via
  the test module's compile-time use of the public surface).
  """

  use ExUnit.Case, async: true

  @test_source """
  defmodule TestMetaprogram do
    defmacro __using__(_) do
      quote do
        def hello(), do: "world"
        def goodbye(), do: "bye"
      end
    end

    def public_fn(), do: :ok

    defpmacro private_macro(_) do
      quote do
        defmacro_inside()
      end
    end
  end
  """

  test "extract_quote_blocks finds top-level quote blocks" do
    blocks = Delfos.MCP.Tools.extract_quote_blocks(@test_source)
    assert length(blocks) >= 2
  end

  test "metaprogrammed? returns true for names inside quote blocks" do
    assert Delfos.MCP.Tools.metaprogrammed?(@test_source, "hello") == true
    assert Delfos.MCP.Tools.metaprogrammed?(@test_source, "goodbye") == true
    assert Delfos.MCP.Tools.metaprogrammed?(@test_source, "defmacro_inside") == true
  end

  test "metaprogrammed? returns false for names not in quote blocks" do
    refute Delfos.MCP.Tools.metaprogrammed?(@test_source, "public_fn")
    refute Delfos.MCP.Tools.metaprogrammed?(@test_source, "nonexistent_fn")
  end

  test "empty source returns no false positives" do
    refute Delfos.MCP.Tools.metaprogrammed?("", "hello")
    assert Delfos.MCP.Tools.extract_quote_blocks("") == []
  end
end
