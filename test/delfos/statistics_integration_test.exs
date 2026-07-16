defmodule Delfos.StatisticsIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  import ExUnit.CaptureIO

  alias Delfos.{Factory, Repo, RepoStarter, Statistics}
  alias Delfos.CLI.Commands.Stadistics
  alias Delfos.Schema.{Chunk, File}

  setup_all do
    assert {:ok, _pid} = RepoStarter.start_repo()
    :ok
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    :ok
  end

  test "records and aggregates successful, failed and timed-out MCP calls" do
    project =
      Factory.insert!(:project,
        name: "statistics_project",
        path: "/tmp/statistics_project"
      )

    file =
      Repo.insert!(%File{
        project_id: project.id,
        path: "lib/statistics.ex",
        language: "elixir",
        line_count: 100,
        size_bytes: 400,
        content_hash: "statistics-hash"
      })

    Repo.insert!(%Chunk{
      project_id: project.id,
      file_id: file.id,
      content: String.duplicate("a", 400),
      token_count: 100,
      chunk_index: 0
    })

    assert :ok =
             Statistics.record_call(
               project,
               "delfos_search",
               {:ok, String.duplicate("b", 40)},
               25
             )

    assert :ok =
             Statistics.record_call(project, "delfos_search", {:error, "not stored"}, 15)

    assert :ok =
             Statistics.record_call(
               project,
               "delfos_search",
               {:error, "not stored"},
               30_000,
               :timeout
             )

    usage = Statistics.usage_snapshot(project.id)

    assert usage.total_calls == 3
    assert usage.success_calls == 1
    assert usage.error_calls == 1
    assert usage.timeout_calls == 1
    assert usage.response_tokens == 10
    assert usage.saved_tokens == 90
    assert usage.estimated_saved_time_ms == 90
    assert usage.total_duration_ms == 30_040
    assert usage.max_duration_ms == 30_000
    assert usage.last_used_at
    assert usage.per_tool == %{"delfos_search" => 3}

    index = Statistics.index_snapshot(project)
    assert index.files == 1
    assert index.lines_of_code == 100
    assert index.source_bytes == 400
    assert index.chunks == 1
    assert index.knowledge_base_tokens == 100
    assert index.languages == [{"elixir", 1}]
  end

  test "CLI lists projects and rejects an unknown project without halting the VM" do
    Factory.insert!(:project,
      name: "listed_statistics_project",
      path: "/tmp/listed_statistics_project"
    )

    list_output =
      capture_io(fn ->
        assert :ok = Stadistics.run_with_opts(%{project: "", list: true, all: false})
      end)

    assert list_output =~ "listed_statistics_project"

    error_output =
      capture_io(fn ->
        assert {:error, :unknown_project} =
                 Stadistics.run_with_opts(%{
                   project: "missing_statistics_project",
                   list: false,
                   all: false
                 })
      end)

    assert error_output =~ "Unknown project"
    assert error_output =~ "--list"
  end
end
