defmodule Delfos.Repo.Migrations.CreateAgentSessions do
  use Ecto.Migration

  def up do
    create table(:agent_sessions, primary_key: false) do
      add :id,             :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :project_id,     references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :query,          :text
      add :retrieved_ids,  {:array, :uuid}, default: []
      add :was_useful,     :boolean
      add :metadata,       :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:agent_sessions, [:project_id])
  end

  def down, do: drop table(:agent_sessions)
end
