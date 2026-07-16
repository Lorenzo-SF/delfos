defmodule Delfos.Repo.Migrations.CreateMcpUsageEvents do
  use Ecto.Migration

  def change do
    create table(:mcp_usage_events, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))

      add(:project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false)

      add(:tool_name, :string, null: false)
      add(:status, :string, null: false)
      add(:response_tokens, :bigint, null: false, default: 0)
      add(:saved_tokens, :bigint, null: false, default: 0)
      add(:duration_ms, :bigint, null: false, default: 0)

      timestamps(type: :utc_datetime)
    end

    create(
      constraint(:mcp_usage_events, :mcp_usage_events_valid_status,
        check: "status IN ('success', 'error', 'timeout')"
      )
    )

    create(
      constraint(:mcp_usage_events, :mcp_usage_events_non_negative_tokens,
        check: "response_tokens >= 0 AND saved_tokens >= 0"
      )
    )

    create(
      constraint(:mcp_usage_events, :mcp_usage_events_non_negative_duration,
        check: "duration_ms >= 0"
      )
    )

    create(index(:mcp_usage_events, [:project_id, :inserted_at]))
    create(index(:mcp_usage_events, [:project_id, :tool_name]))
  end
end
