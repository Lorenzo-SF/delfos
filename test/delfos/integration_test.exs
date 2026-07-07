defmodule Delfos.IntegrationTest do
  @moduledoc """
  Integration tests for Delfos public API surface.

  These tests do NOT require a running Postgres instance — they exercise
  the pure-Elixir modules (parsers, scanner, hybrid search result shape).
  Tests that DO require Postgres are tagged with `@tag :integration`.

  Run with `mix test` (default) for these; `mix test --include integration`
  for the full suite including DB-touching tests.
  """
  use ExUnit.Case, async: true

  alias Delfos.Indexer.Scanner
  alias Delfos.Parsers.Dispatcher

  describe "MCP Tools — graceful failure when no project" do
    test "search/2 with nil project returns error tuple" do
      assert Delfos.MCP.Tools.search(nil, %{"query" => "test"}) ==
               {:error, "No hay proyectos indexados. Ejecuta: delfos init"}
    end

    test "all 8 tools return {:error, _} when project is nil" do
      tools_with_args = [
        {:search, %{"query" => "test"}},
        {:symbol, %{"name" => "Foo"}},
        {:context, %{"task" => "refactor"}},
        {:callers, %{"name" => "Foo"}},
        {:callees, %{"name" => "Foo"}},
        {:impact, %{"name" => "Foo"}},
        {:audit, %{}},
        {:files, %{}}
      ]

      for {fun, args} <- tools_with_args do
        result = apply(Delfos.MCP.Tools, fun, [nil, args])

        assert match?({:error, _}, result),
               "Expected #{fun} to return error tuple, got: #{inspect(result)}"
      end
    end

    test "impact/2 with nil project returns proper error message" do
      assert Delfos.MCP.Tools.impact(nil, %{"name" => "Foo"}) ==
               {:error, "No hay proyectos indexados"}
    end
  end

  describe "Parsers.Dispatcher" do
    test "language/1 identifies elixir files" do
      assert Dispatcher.language("lib/foo.ex") == "elixir"
      assert Dispatcher.language("config/config.exs") == "elixir"
      assert Dispatcher.language("test/foo_test.exs") == "elixir"
    end

    test "language/1 identifies common file types" do
      assert Dispatcher.language("foo.py") == "python"
      assert Dispatcher.language("foo.ts") == "typescript"
      assert Dispatcher.language("foo.js") == "javascript"
      assert Dispatcher.language("foo.rs") == "rust"
      assert Dispatcher.language("foo.go") == "go"
      assert Dispatcher.language("foo.yml") == "config"
    end

    test "language/1 returns 'unknown' for unrecognized extensions" do
      assert Dispatcher.language("foo.png") == "unknown"
      assert Dispatcher.language("foo.bin") == "unknown"
      assert Dispatcher.language("no_extension") == "unknown"
    end

    test "supported?/1 returns true for known extensions" do
      assert Dispatcher.supported?("lib/foo.ex")
      assert Dispatcher.supported?("src/foo.ts")
      assert Dispatcher.supported?("lib/foo.py")
    end

    test "supported?/1 returns false for unknown extensions" do
      refute Dispatcher.supported?("image.png")
      refute Dispatcher.supported?("data.bin")
      refute Dispatcher.supported?("README.md")
    end

    test "parse/2 for elixir returns ok tuple with expected shape" do
      content = """
      defmodule Foo do
        @moduledoc "Test module"

        def hello, do: :world
        defp private_helper(x), do: x + 1
      end
      """

      assert {:ok, parsed} = Dispatcher.parse("lib/foo.ex", content)
      assert is_list(parsed.symbols)
      assert is_list(parsed.docs)
      assert is_list(parsed.todos)
      assert is_integer(parsed.line_count)
      assert parsed.language == "elixir"
    end

    test "parse/2 for unsupported extensions returns error" do
      assert {:error, :unsupported_extension} =
               Dispatcher.parse("image.png", "binary content")
    end
  end

  describe "Retrieval.Reranker" do
    test "rrf_merge/2 returns empty list for empty inputs" do
      result =
        Delfos.Retrieval.Reranker.rrf_merge(
          %{vector: [], bm25: [], graph: []},
          weights: %{vector: 0.55, bm25: 0.25, graph: 0.20},
          k: 5
        )

      assert result == []
    end

    test "rrf_merge/2 merges and deduplicates by id" do
      items = [%{id: "a", content: "foo", score: 0.9}]

      result =
        Delfos.Retrieval.Reranker.rrf_merge(
          %{vector: items, bm25: items, graph: []},
          weights: %{vector: 0.55, bm25: 0.25, graph: 0.20},
          k: 5
        )

      assert length(result) == 1
      [merged] = result
      assert merged.id == "a"
      assert Map.has_key?(merged, :combined_score)
    end

    test "rrf_merge/2 sorts by combined_score descending" do
      items_low = [%{id: "low", content: "x", score: 0.1}]
      items_high = [%{id: "high", content: "y", score: 0.9}]

      result =
        Delfos.Retrieval.Reranker.rrf_merge(
          %{vector: items_high, bm25: items_low, graph: []},
          weights: %{vector: 0.55, bm25: 0.25, graph: 0.20},
          k: 5
        )

      assert length(result) == 2
      [first, second] = result
      assert first.id == "high"
      assert second.id == "low"
      assert first.combined_score > second.combined_score
    end

    test "rrf_merge/2 respects k limit" do
      items = for i <- 1..20, do: %{id: "id_#{i}", content: "c", score: i * 0.1}

      result =
        Delfos.Retrieval.Reranker.rrf_merge(
          %{vector: items, bm25: [], graph: []},
          weights: %{vector: 1.0, bm25: 0.0, graph: 0.0},
          k: 5
        )

      assert length(result) == 5
    end
  end

  describe "Indexer.Scanner" do
    test "find_files/1 locates elixir files in temp dir" do
      dir = Path.join(System.tmp_dir!(), "delfos_test_#{:rand.uniform(99_999)}")
      File.mkdir_p!(Path.join(dir, "lib"))

      on_exit(fn -> File.rm_rf!(dir) end)

      File.write!(Path.join([dir, "lib", "foo.ex"]), "defmodule Foo do\nend\n")
      File.write!(Path.join([dir, "lib", "bar.ex"]), "defmodule Bar do\nend\n")
      File.write!(Path.join([dir, "README.md"]), "# Not indexable")

      files = Scanner.find_files(dir)

      assert Enum.any?(files, &String.ends_with?(&1, "foo.ex"))
      assert Enum.any?(files, &String.ends_with?(&1, "bar.ex"))
      refute Enum.any?(files, &String.ends_with?(&1, "README.md"))
    end
  end

  describe "HybridSearch — Arrea.run_sync API (C-2 audit fix)" do
    test "arrea exports run_sync/2 as public facade" do
      Code.ensure_loaded!(Arrea)

      assert function_exported?(Arrea, :run_sync, 2),
             "Arrea.run_sync/2 must be exported (public facade)"
    end
  end
end
