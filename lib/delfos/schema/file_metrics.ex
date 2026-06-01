defmodule Delfos.Schema.FileMetrics do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "file_metrics" do
    field(:afferent_coupling, :integer, default: 0)
    field(:efferent_coupling, :integer, default: 0)
    field(:instability, :float, default: 0.0)
    field(:in_cycle, :boolean, default: false)
    field(:test_coverage_est, :float)
    field(:todo_count, :integer, default: 0)
    field(:complexity_score, :float, default: 0.0)
    field(:debt_score, :float, default: 0.0)

    belongs_to(:file, Delfos.Schema.File)
    belongs_to(:project, Delfos.Schema.Project)

    timestamps(type: :utc_datetime)
  end

  def changeset(metrics, attrs) do
    metrics
    |> cast(attrs, [
      :file_id,
      :project_id,
      :afferent_coupling,
      :efferent_coupling,
      :instability,
      :in_cycle,
      :test_coverage_est,
      :todo_count,
      :complexity_score,
      :debt_score
    ])
    |> validate_required([:file_id, :project_id])
    |> unique_constraint(:file_id)
  end
end
