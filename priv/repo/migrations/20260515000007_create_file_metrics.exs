defmodule Delfos.Repo.Migrations.CreateFileMetrics do
  use Ecto.Migration

  def up do
    create table(:file_metrics, primary_key: false) do
      add :id,                  :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :file_id,             references(:files,    type: :uuid, on_delete: :delete_all), null: false
      add :project_id,          references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :afferent_coupling,   :integer, default: 0
      add :efferent_coupling,   :integer, default: 0
      add :instability,         :float,   default: 0.0
      add :in_cycle,            :boolean, default: false
      add :test_coverage_est,   :float
      add :todo_count,          :integer, default: 0
      add :complexity_score,    :float, default: 0.0
      add :debt_score,          :float, default: 0.0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:file_metrics, [:file_id])
    create index(:file_metrics, [:project_id, :debt_score])
  end

  def down, do: drop table(:file_metrics)
end
