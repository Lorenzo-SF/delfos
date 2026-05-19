defmodule Delfos.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def up do
    create table(:files, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :path, :string, null: false
      add :language, :string
      add :size_bytes, :bigint
      add :line_count, :integer
      add :last_modified, :utc_datetime
      add :last_indexed, :utc_datetime
      add :content_hash, :string
      add :git_churn, :integer, default: 0
      add :git_authors, {:array, :string}, default: []
      add :risk_score, :float, default: 0.0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:files, [:project_id, :path])
    create index(:files, [:project_id, :risk_score])
  end

  def down, do: drop table(:files)
end
