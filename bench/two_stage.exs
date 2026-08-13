# Bench: Single-stage vs two-stage indexer pipeline
#
# Simulates real worker behavior with actual Task.async_stream.
# CPU work: parse (5ms per file via Process.sleep).
# I/O work: embed_batch (50ms per file).
#
# Measures wall-clock time for both architectures.

defmodule Bench.TwoStage do
  def run do
    sizes = [50, 100, 200]
    parse_ms = 5
    embed_ms = 50

    Enum.each(sizes, fn n ->
      IO.puts("\n=== #{n} files, parse=#{parse_ms}ms, embed=#{embed_ms}ms ===")

      # Single-stage: each worker does parse + embed per file
      single_time = single_stage(n, parse_ms, embed_ms, 8)
      IO.puts("Single-stage (8 workers):  #{single_time} ms")

      # Two-stage: 8 parse workers + 16 embed workers
      two_time = two_stage(n, parse_ms, embed_ms, 8, 16)
      IO.puts("Two-stage (8 parse + 16 embed): #{two_time} ms")

      speedup = if two_time > 0, do: Float.round(single_time / two_time, 2), else: 1.0
      IO.puts("Speedup: #{speedup}x")
    end)
  end

  defp time(fun) do
    {t_us, _} = :timer.tc(fun)
    round(t_us / 1000)
  end

  defp single_stage(n_files, parse_ms, embed_ms, workers) do
    time(fn ->
      1..n_files
      |> Task.async_stream(
        fn _file ->
          Process.sleep(parse_ms)
          Process.sleep(embed_ms)
          :ok
        end,
        max_concurrency: workers,
        on_timeout: :kill_task
      )
      |> Stream.run()
    end)
  end

  defp two_stage(n_files, parse_ms, embed_ms, parse_w, embed_w) do
    time(fn ->
      # Stage 1: parse all files
      stage1_done =
        1..n_files
        |> Task.async_stream(
          fn _file ->
            Process.sleep(parse_ms)
            :parsed
          end,
          max_concurrency: parse_w,
          on_timeout: :kill_task
        )
        |> Enum.to_list()

      # Stage 2: embed each parsed file
      stage1_done
      |> Task.async_stream(
        fn _parsed ->
          Process.sleep(embed_ms)
          :ok
        end,
        max_concurrency: embed_w,
        on_timeout: :kill_task
      )
      |> Stream.run()
    end)
  end
end

Bench.TwoStage.run()
