defmodule Delfos.Repo.Migrations.AddMcpUsageEventAuditFields do
  use Ecto.Migration

  @moduledoc """
  SE-3 (S3): adds args + caller_pid to mcp_usage_events for audit log.

  Without these columns, the only signal after a tool call is
  \"tool X was called\". To investigate \"who called what with
  what args\" we'd have to grep logs (which often don't have the
  args for privacy/size reasons).

  `args` is stored as text (JSON-encoded map). We could use jsonb
  but text is simpler for a one-column add and is enough for
  audit purposes (no need to query inside the JSON).

  `caller_pid` is the BEAM process pid of the caller. Useful when
  the same user runs delfos from multiple shells — they have
  different BEAM pids. Stored as text because pid is technically
  a reference, not an integer.
  """

  def change do
    alter table(:mcp_usage_events) do
      add(:args, :text)
      add(:caller_pid, :string)
    end
  end
end
