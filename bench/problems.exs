# Bench: Problem case scenarios
#
# Exercises paths likely to expose performance issues, edge cases,
# or correctness bugs. Each scenario runs against a generated fixture.
#
# Usage:  mix run bench/problems.exs

Code.require_file("fixtures.exs", "bench/")

defmodule Bench.Problems do
  @moduledoc """
  Each scenario is a focused stress test for one likely problem area.
  Run with `mix run bench/problems.exs` (≈2 minutes total).
  """

  def run_all do
    IO.puts("\n=== Scenario 1: very large file (AST memory) ===")
    scenario_large_file()

    IO.puts("\n=== Scenario 2: deeply nested directory (Scanner depth) ===")
    scenario_deep_nesting()

    IO.puts("\n=== Scenario 3: project with zero eligible files ===")
    scenario_empty_project()

    IO.puts("\n=== Scenario 4: project with duplicates (cache hit rate) ===")
    scenario_duplicates()

    IO.puts("\n=== Scenario 5: concurrent embeddings (Finch pool) ===")
    scenario_concurrent_embeds()

    IO.puts("\n=== Scenario 6: unicode/emoji in source ===")
    scenario_unicode()
  end

  # 1. AST memory on a single very large file. AST construction is the
  # main memory consumer; expect ~50-80 KB per file. 10k lines ≈ 700 KB.
  def scenario_large_file do
    Bench.Fixtures.build_file("bench/fixtures/large_single.ex", line_count: 10_000)
    {time_us, _} = :timer.tc(fn ->
      "bench/fixtures/large_single.ex"
      |> File.read!()
      |> Code.string_to_quoted!()
      :ok
    end)

    size = File.stat!("bench/fixtures/large_single.ex").size
    IO.puts("File: #{div(size, 1024)} KB, AST parse: #{div(time_us, 1000)} ms")

    # Cleanup so this scenario doesn't pollute later ones
    File.rm!("bench/fixtures/large_single.ex")
  end

  # 2. Directory depth at the max_depth boundary. Scanner should NOT
  # silently truncate (the bug fixed in commit 069ac95).
  def scenario_deep_nesting do
    base = "bench/fixtures/deep"
    File.rm_rf!(base)
    File.mkdir_p!(base)

    # Build 60 levels deep (exceeds default max_depth=50)
    Enum.reduce(1..60, base, fn i, parent ->
      child = Path.join(parent, "level_#{i}")
      File.mkdir_p!(child)

      # Drop a file at the bottom
      if i == 60, do: File.write!(Path.join(child, "leaf.ex"), "defmodule L do\nend\n")
      child
    end)

    {time_us, count} = :timer.tc(fn ->
      base
      |> Delfos.Indexer.Scanner.stream_files()
      |> Enum.count()
    end)

    IO.puts("60-level deep: #{div(time_us, 1000)} ms, found #{count} file(s)")

    File.rm_rf!(base)
  end

  # 3. Project path with no .ex files. Scanner should return empty
  # without crashing.
  def scenario_empty_project do
    base = "bench/fixtures/empty_proj"
    File.rm_rf!(base)
    File.mkdir_p!(base)
    File.write!(Path.join(base, "README.md"), "# Empty\n")

    {time_us, count} = :timer.tc(fn ->
      base
      |> Delfos.Indexer.Scanner.stream_files()
      |> Enum.count()
    end)

    IO.puts("Empty project: #{div(time_us, 1000)} ms, found #{count} file(s) (expected 0)")

    File.rm_rf!(base)
  end

  # 4. Many files with identical content. Embeddings cache should
  # skip re-embedding. Measures cache effectiveness.
  def scenario_duplicates do
    content = "defmodule Same do\n  def f(x), do: x + 1\nend\n"
    base = "bench/fixtures/dupes"
    File.rm_rf!(base)
    File.mkdir_p!(base)

    # 50 files, all with identical content
    Enum.each(1..50, fn i ->
      File.write!(Path.join(base, "m_#{i}.ex"), content)
    end)

    # Pre-fill the cache with the same content 50 times.
    # If cache works, second+ lookups are O(1).
    Delfos.Embeddings.Cache.clear()

    {time_us, _} = :timer.tc(fn ->
      Enum.each(1..50, fn _i ->
        # lookup_batch exercises the cache; with 50 identical texts,
        # the cache should return all hits after the first insert.
        results = Delfos.Embeddings.Cache.lookup_batch(List.duplicate(content, 10))
        # First lookup is miss; insert; subsequent are hits
        miss_count = Enum.count(results, &(&1 == :miss))
        if miss_count > 0, do: Delfos.Embeddings.Cache.put(content, List.duplicate(0.5, 768))
        results
      end)
    end)

    stats = Delfos.Embeddings.Cache.stats()
    IO.puts("""
    50 identical files: #{div(time_us, 1000)} ms
    cache stats: size=#{stats.size} hits=#{stats.hits} misses=#{stats.misses} puts=#{stats.puts}
    """)

    Delfos.Embeddings.Cache.clear()
    File.rm_rf!(base)
  end

  # 5. Many concurrent embed calls. With default Finch pool (50) and
  # Ollama local, this exercises the HTTP pool. If connections leak,
  # memory grows unbounded.
  def scenario_concurrent_embeds do
    n = 100

    {time_us, _} = :timer.tc(fn ->
      1..n
      |> Task.async_stream(
        fn _i ->
          # Stub: do nothing expensive; we're just measuring pool usage
          Process.sleep(1)
          :ok
        end,
        max_concurrency: 32,
        timeout: 10_000
      )
      |> Stream.run()
    end)

    IO.puts("#{n} concurrent tasks @ 32 workers: #{div(time_us, 1000)} ms")
  end

  # 6. Unicode in source code (emojis, accented chars, CJK). Parser
  # should handle UTF-8 without line-count off-by-one.
  def scenario_unicode do
    content = """
    defmodule M do
      @moduledoc "Módulo con acentos: ñ, é, ü. 中文日本語한국어 🚀"
      def saludo, do: "¡Hola! 🎉"
      def emoji_test, do: :😀
      def width_test, do: "你好"  # CJK characters
    end
    """

    path = "bench/fixtures/unicode_test.ex"
    File.write!(path, content)

    result = Delfos.Parsers.ElixirParser.parse(path, content)

    IO.puts("""
    Unicode parse: line_count=#{result.line_count} (expected ~9), symbols=#{length(result.symbols)}
    """)

    File.rm!(path)
  end

  def run, do: run_all()
end

Bench.Problems.run()
