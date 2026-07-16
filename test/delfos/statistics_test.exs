defmodule Delfos.StatisticsTest do
  use ExUnit.Case, async: true

  alias Delfos.Schema.McpUsageEvent
  alias Delfos.Statistics

  describe "estimate_tokens/1" do
    test "uses a ceiling four-character estimate" do
      assert Statistics.estimate_tokens("") == 0
      assert Statistics.estimate_tokens("a") == 1
      assert Statistics.estimate_tokens("abcd") == 1
      assert Statistics.estimate_tokens("abcde") == 2
      assert Statistics.estimate_tokens(nil) == 0
    end
  end

  describe "estimated_saved_time_ms/1" do
    test "uses the documented 1,000 context tokens per second baseline" do
      assert Statistics.saved_time_baseline_tokens_per_second() == 1_000
      assert Statistics.estimated_saved_time_ms(0) == 0
      assert Statistics.estimated_saved_time_ms(1_000) == 1_000
      assert Statistics.estimated_saved_time_ms(2_500) == 2_500
    end
  end

  describe "record_call/5" do
    test "is a no-op when there is no active project" do
      assert Statistics.record_call(nil, "delfos_search", {:ok, "result"}, 12) == :ok
      assert Statistics.record_call_async(nil, "delfos_search", {:error, "boom"}, 12) == :ok
    end
  end

  describe "McpUsageEvent.changeset/2" do
    test "accepts valid local aggregate data" do
      changeset =
        McpUsageEvent.changeset(%McpUsageEvent{}, %{
          project_id: Ecto.UUID.generate(),
          tool_name: "delfos_context",
          status: "success",
          response_tokens: 10,
          saved_tokens: 90,
          duration_ms: 25
        })

      assert changeset.valid?
    end

    test "rejects invalid status and negative counters" do
      changeset =
        McpUsageEvent.changeset(%McpUsageEvent{}, %{
          project_id: Ecto.UUID.generate(),
          tool_name: "delfos_context",
          status: "unknown",
          response_tokens: -1,
          saved_tokens: -1,
          duration_ms: -1
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
      assert "must be greater than or equal to 0" in errors_on(changeset).response_tokens
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
