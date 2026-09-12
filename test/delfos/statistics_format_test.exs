defmodule Delfos.StatisticsFormatTest do
  use ExUnit.Case, async: true

  alias Delfos.Statistics

  describe "format_summary/1 (iter-051 public formatter)" do
    test "formats a summary with all fields" do
      summary = %{
        tools: %{"search" => 5, "embed" => 2},
        queries: 7,
        tokens_saved: 1000
      }

      result = Statistics.format_summary(summary)

      assert result =~ "Tools tracked: 2"
      assert result =~ "Total queries: 7"
      assert result =~ "Total tokens saved: 1000"
    end

    test "handles missing tokens_saved gracefully" do
      summary = %{tools: %{}, queries: 0}
      result = Statistics.format_summary(summary)
      assert result =~ "Total tokens saved: 0"
    end
  end

  describe "format_bytes/1 (iter-051 byte formatter)" do
    test "formats bytes < 1KB" do
      assert Statistics.format_bytes(0) == "0 B"
      assert Statistics.format_bytes(512) == "512 B"
      assert Statistics.format_bytes(1023) == "1023 B"
    end

    test "formats KB" do
      assert Statistics.format_bytes(1024) == "1.0 KB"
      assert Statistics.format_bytes(1536) == "1.5 KB"
    end

    test "formats MB" do
      assert Statistics.format_bytes(1024 * 1024) == "1.0 MB"
      assert Statistics.format_bytes(2 * 1024 * 1024) == "2.0 MB"
    end
  end
end
