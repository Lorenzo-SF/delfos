defmodule Delfos.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def up do
    create table(:relationships, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :from_id, references(:symbols, type: :uuid, on_delete: :delete_all), null: false
      add :to_id, references(:symbols, type: :uuid, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :weight, :float, default: 1.0
      add :metadata, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:relationships, [:from_id, :to_id, :kind])
    create index(:relationships, [:project_id, :from_id, :kind])
    create index(:relationships, [:project_id, :to_id, :kind])
  end

  def down, do: drop table(:relationships)
end
