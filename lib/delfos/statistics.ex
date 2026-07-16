defmodule Delfos.Statistics do
  @moduledoc """
  Collects and aggregates project-local MCP usage statistics.

  Only numeric aggregates and tool names are persisted. Queries, arguments,
  source code, responses and error messages are never stored.

  Token counts are estimates based on four characters per token. Saved tokens
  compare each successful response with loading the project's complete indexed
  knowledge base. Estimated saved time uses a documented baseline of 1,000
  context tokens per second.
  """

  import Ecto.Query
  require Logger

  alias Delfos.Repo

  alias Delfos.Schema.{
    Chunk,
    File,
    FileMetrics,
    McpUsageEvent,
    Project,
    Relationship,
    Symbol
  }

  @saved_time_baseline_tokens_per_second 1_000

  @doc "Returns the baseline used to derive estimated saved time."
  def saved_time_baseline_tokens_per_second,
    do: @saved_time_baseline_tokens_per_second

  @doc "Estimates tokens using the same four-characters-per-token heuristic as the indexer."
  @spec estimate_tokens(term()) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) and text != "",
    do: ceil_div(String.length(text), 4)

  def estimate_tokens(_text), do: 0

  @doc "Converts estimated saved context tokens to milliseconds at 1,000 tokens/second."
  @spec estimated_saved_time_ms(term()) :: non_neg_integer()
  def estimated_saved_time_ms(tokens) when is_integer(tokens) and tokens > 0,
    do: div(tokens * 1_000, @saved_time_baseline_tokens_per_second)

  def estimated_saved_time_ms(_tokens), do: 0

  @doc "Returns the estimated number of tokens represented by the local knowledge base."
  @spec knowledge_base_tokens(Ecto.UUID.t()) :: non_neg_integer()
  def knowledge_base_tokens(project_id) do
    chunk_tokens =
      Repo.one(
        from(c in Chunk,
          where: c.project_id == ^project_id,
          select: coalesce(sum(c.token_count), 0)
        )
      )
      |> non_negative_integer()

    if chunk_tokens > 0 do
      chunk_tokens
    else
      source_bytes =
        Repo.one(
          from(f in File,
            where: f.project_id == ^project_id,
            select: coalesce(sum(f.size_bytes), 0)
          )
        )
        |> non_negative_integer()

      ceil_div(source_bytes, 4)
    end
  end

  @doc """
  Records one completed MCP call without allowing persistence failures to affect MCP.

  `status` may be `:success`, `:error`, `:timeout` or their string forms. When it
  is omitted, the status is inferred from `result`.
  """
  @spec record_call(struct() | Ecto.UUID.t() | nil, String.t(), term(), integer(), term()) ::
          :ok
  def record_call(project, tool_name, result, duration_ms, status \\ nil) do
    with project_id when is_binary(project_id) <- project_id(project),
         normalized_status <- normalize_status(status, result) do
      response_tokens = response_tokens(normalized_status, result)

      saved_tokens =
        if normalized_status == "success" do
          max(knowledge_base_tokens(project_id) - response_tokens, 0)
        else
          0
        end

      attrs = %{
        project_id: project_id,
        tool_name: to_string(tool_name),
        status: normalized_status,
        response_tokens: response_tokens,
        saved_tokens: saved_tokens,
        duration_ms: max(normalize_duration(duration_ms), 0)
      }

      %McpUsageEvent{}
      |> McpUsageEvent.changeset(attrs)
      |> Repo.insert()

      :ok
    else
      _ -> :ok
    end
  rescue
    error ->
      Logger.debug("MCP statistics were not persisted: #{Exception.message(error)}")
      :ok
  catch
    :exit, reason ->
      Logger.debug("MCP statistics persistence exited: #{inspect(reason)}")
      :ok

    kind, reason ->
      Logger.debug("MCP statistics persistence failed: #{kind}: #{inspect(reason)}")
      :ok
  end

  @doc "Records a call in a supervised background task so the MCP response is not delayed."
  @spec record_call_async(struct() | Ecto.UUID.t() | nil, String.t(), term(), integer(), term()) ::
          :ok
  def record_call_async(project, tool_name, result, duration_ms, status \\ nil) do
    operation = fn -> record_call(project, tool_name, result, duration_ms, status) end

    case Process.whereis(Delfos.TaskSupervisor) do
      nil -> Task.start(operation)
      _pid -> Task.Supervisor.start_child(Delfos.TaskSupervisor, operation)
    end

    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
    _, _ -> :ok
  end

  @doc "Aggregates persisted MCP usage for one project."
  @spec usage_snapshot(Ecto.UUID.t()) :: map()
  def usage_snapshot(project_id) do
    aggregate =
      Repo.one(
        from(e in McpUsageEvent,
          where: e.project_id == ^project_id,
          select: %{
            total_calls: count(e.id),
            success_calls: sum(fragment("CASE WHEN ? = 'success' THEN 1 ELSE 0 END", e.status)),
            error_calls: sum(fragment("CASE WHEN ? = 'error' THEN 1 ELSE 0 END", e.status)),
            timeout_calls: sum(fragment("CASE WHEN ? = 'timeout' THEN 1 ELSE 0 END", e.status)),
            response_tokens: sum(e.response_tokens),
            saved_tokens: sum(e.saved_tokens),
            total_duration_ms: sum(e.duration_ms),
            avg_duration_ms: avg(e.duration_ms),
            max_duration_ms: max(e.duration_ms),
            last_used_at: max(e.inserted_at)
          }
        )
      ) || %{}

    total_calls = non_negative_integer(aggregate[:total_calls])
    success_calls = non_negative_integer(aggregate[:success_calls])

    per_tool =
      Repo.all(
        from(e in McpUsageEvent,
          where: e.project_id == ^project_id,
          group_by: e.tool_name,
          order_by: [desc: count(e.id), asc: e.tool_name],
          select: {e.tool_name, count(e.id)}
        )
      )
      |> Map.new()

    %{
      total_calls: total_calls,
      success_calls: success_calls,
      error_calls: non_negative_integer(aggregate[:error_calls]),
      timeout_calls: non_negative_integer(aggregate[:timeout_calls]),
      success_rate: percentage(success_calls, total_calls),
      response_tokens: non_negative_integer(aggregate[:response_tokens]),
      saved_tokens: non_negative_integer(aggregate[:saved_tokens]),
      estimated_saved_time_ms:
        estimated_saved_time_ms(non_negative_integer(aggregate[:saved_tokens])),
      total_duration_ms: non_negative_integer(aggregate[:total_duration_ms]),
      avg_duration_ms: non_negative_number(aggregate[:avg_duration_ms]),
      max_duration_ms: non_negative_integer(aggregate[:max_duration_ms]),
      last_used_at: aggregate[:last_used_at],
      per_tool: per_tool
    }
  end

  @doc "Returns current, measurable index statistics for a project."
  @spec index_snapshot(struct()) :: map()
  def index_snapshot(%Project{id: project_id} = project) do
    files_query = from(f in File, where: f.project_id == ^project_id)
    symbols_query = from(s in Symbol, where: s.project_id == ^project_id)
    chunks_query = from(c in Chunk, where: c.project_id == ^project_id)
    relationships_query = from(r in Relationship, where: r.project_id == ^project_id)
    metrics_query = from(m in FileMetrics, where: m.project_id == ^project_id)

    files = Repo.aggregate(files_query, :count, :id)
    symbols = Repo.aggregate(symbols_query, :count, :id)

    embedded_symbols =
      Repo.aggregate(where(symbols_query, [s], not is_nil(s.embedding)), :count, :id)

    summarized_symbols =
      Repo.aggregate(where(symbols_query, [s], not is_nil(s.summary)), :count, :id)

    last_indexed_at =
      Repo.one(from(f in files_query, select: max(f.last_indexed))) || project.last_scanned

    languages =
      Repo.all(
        from(f in files_query,
          where: not is_nil(f.language),
          group_by: f.language,
          order_by: [desc: count(f.id), asc: f.language],
          select: {f.language, count(f.id)}
        )
      )

    %{
      files: non_negative_integer(files),
      lines_of_code: aggregate_sum(files_query, :line_count),
      source_bytes: aggregate_sum(files_query, :size_bytes),
      symbols: non_negative_integer(symbols),
      chunks: non_negative_integer(Repo.aggregate(chunks_query, :count, :id)),
      relationships: non_negative_integer(Repo.aggregate(relationships_query, :count, :id)),
      knowledge_base_tokens: knowledge_base_tokens(project_id),
      embedded_symbols: non_negative_integer(embedded_symbols),
      embedding_coverage: percentage(embedded_symbols, symbols),
      summarized_symbols: non_negative_integer(summarized_symbols),
      summary_coverage: percentage(summarized_symbols, symbols),
      languages: languages,
      cycle_files:
        non_negative_integer(
          Repo.aggregate(where(metrics_query, [m], m.in_cycle == true), :count, :id)
        ),
      todos: aggregate_sum(metrics_query, :todo_count),
      last_updated_at: last_indexed_at
    }
  end

  defp aggregate_sum(query, field) do
    query
    |> Repo.aggregate(:sum, field)
    |> non_negative_integer()
  end

  defp project_id(%Project{id: id}), do: id
  defp project_id(id) when is_binary(id), do: id
  defp project_id(_project), do: nil

  defp normalize_status(nil, {:ok, _text}), do: "success"
  defp normalize_status(nil, _result), do: "error"
  defp normalize_status(status, _result) when status in [:success, "success"], do: "success"
  defp normalize_status(status, _result) when status in [:timeout, "timeout"], do: "timeout"
  defp normalize_status(_status, _result), do: "error"

  defp response_tokens("success", {:ok, text}), do: estimate_tokens(text)
  defp response_tokens(_status, _result), do: 0

  defp normalize_duration(duration_ms) when is_integer(duration_ms), do: duration_ms
  defp normalize_duration(duration_ms) when is_float(duration_ms), do: round(duration_ms)
  defp normalize_duration(_duration_ms), do: 0

  defp non_negative_integer(nil), do: 0
  defp non_negative_integer(%Decimal{} = value), do: max(Decimal.to_integer(value), 0)
  defp non_negative_integer(value) when is_integer(value), do: max(value, 0)
  defp non_negative_integer(value) when is_float(value), do: max(round(value), 0)
  defp non_negative_integer(_value), do: 0

  defp non_negative_number(nil), do: 0.0
  defp non_negative_number(%Decimal{} = value), do: max(Decimal.to_float(value), 0.0)
  defp non_negative_number(value) when is_number(value), do: max(value * 1.0, 0.0)
  defp non_negative_number(_value), do: 0.0

  defp percentage(_part, 0), do: 0.0
  defp percentage(part, total), do: Float.round(non_negative_integer(part) / total * 100, 1)

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
end
