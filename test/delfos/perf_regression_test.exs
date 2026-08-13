defmodule Delfos.PerfRegressionTest do
  @moduledoc """
  Performance regression guards.

  These tests run against the synthetic fixtures in `bench/fixtures/`
  and assert that operations don't exceed a defined threshold. If a
  refactor makes something slower, the test fails with a clear message.

  Thresholds are calibrated against this host (AMD Ryzen AI 9 HX 370,
  24 cores). On slower machines they may need to be relaxed — set
  `PERF_REGRESSION_MULTIPLIER=2.0` to double all thresholds for CI.

  To run:
    mix test test/delfos/perf_regression_test.exs
  """

  use ExUnit.Case, async: false

  @small_threshold_ms 50
  @medium_threshold_ms 100
  @large_threshold_ms 500

  @moduletag :perf

  defp threshold_for(size) do
    multiplier =
      case System.get_env("PERF_REGRESSION_MULTIPLIER") do
        nil -> 1.0
        s -> String.to_float(s)
      end

    case size do
      :small -> round(@small_threshold_ms * multiplier)
      :medium -> round(@medium_threshold_ms * multiplier)
      :large -> round(@large_threshold_ms * multiplier)
    end
  end

  test "Scanner.find_files medium (100 files) under threshold" do
    {time_us, _} =
      :timer.tc(fn ->
        "bench/fixtures/medium"
        |> Delfos.Indexer.Scanner.find_files()
        |> Enum.to_list()
      end)

    time_ms = round(time_us / 1000)
    threshold = threshold_for(:medium)

    assert time_ms < threshold,
           "Scanner.find_files medium took #{time_ms}ms, threshold is #{threshold}ms"
  end

  test "Scanner.stream_files medium (100 files) under threshold" do
    {time_us, _} =
      :timer.tc(fn ->
        "bench/fixtures/medium"
        |> Delfos.Indexer.Scanner.stream_files()
        |> Enum.to_list()
      end)

    time_ms = round(time_us / 1000)
    threshold = threshold_for(:medium)

    assert time_ms < threshold,
           "Scanner.stream_files medium took #{time_ms}ms, threshold is #{threshold}ms"
  end

  test "Parser medium (100 files) under threshold" do
    files = File.ls!("bench/fixtures/medium/lib")

    {time_us, _} =
      :timer.tc(fn ->
        Enum.each(files, fn file ->
          path = Path.join("bench/fixtures/medium/lib", file)
          content = File.read!(path)
          Delfos.Parsers.ElixirParser.parse(path, content)
          :ok
        end)
      end)

    time_ms = round(time_us / 1000)
    threshold = threshold_for(:medium)

    assert time_ms < threshold,
           "ElixirParser medium took #{time_ms}ms, threshold is #{threshold}ms"
  end

  test "Large fixture scan + parse under threshold" do
    {time_us, _} =
      :timer.tc(fn ->
        "bench/fixtures/large"
        |> Delfos.Indexer.Scanner.stream_files()
        |> Enum.to_list()
        |> Enum.each(fn path ->
          content = File.read!(path)
          Delfos.Parsers.ElixirParser.parse(path, content)
          :ok
        end)
      end)

    time_ms = round(time_us / 1000)
    threshold = threshold_for(:large)

    assert time_ms < threshold,
           "Scan + parse large (500 files) took #{time_ms}ms, threshold is #{threshold}ms"
  end
end
