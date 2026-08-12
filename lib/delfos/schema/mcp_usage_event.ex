defmodule Delfos.Schema.McpUsageEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mcp_usage_events" do
    field(:tool_name, :string)
    field(:status, :string)
    field(:response_tokens, :integer, default: 0)
    field(:saved_tokens, :integer, default: 0)
    field(:duration_ms, :integer, default: 0)
    # SE-3/S3: args + caller_pid for audit log. `args` is JSON-encoded
    # text (Postgres has jsonb but we use text for simplicity — the
    # schema migration is smaller). `caller_pid` is the BEAM pid that
    # initiated the call (printed as "0.123.0" or similar).
    field(:args, :string)
    field(:caller_pid, :string)

    belongs_to(:project, Delfos.Schema.Project)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :project_id,
      :tool_name,
      :status,
      :response_tokens,
      :saved_tokens,
      :duration_ms,
      :args,
      :caller_pid
    ])
    |> validate_required([
      :project_id,
      :tool_name,
      :status,
      :response_tokens,
      :saved_tokens,
      :duration_ms
    ])
    |> validate_inclusion(:status, ["success", "error", "timeout"])
    |> validate_number(:response_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:saved_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:project_id)
  end
end
