defmodule Delfos.Schema.File do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "files" do
    field(:path, :string)
    field(:language, :string)
    field(:size_bytes, :integer)
    field(:line_count, :integer)
    field(:last_modified, :naive_datetime)
    field(:last_indexed, :naive_datetime)
    field(:content_hash, :string)
    field(:git_churn, :integer, default: 0)
    field(:git_authors, {:array, :string}, default: [])
    field(:risk_score, :float, default: 0.0)

    belongs_to(:project, Delfos.Schema.Project)
    has_many(:symbols, Delfos.Schema.Symbol)
    has_many(:chunks, Delfos.Schema.Chunk)
    has_one(:metrics, Delfos.Schema.FileMetrics)

    timestamps(type: :utc_datetime)
  end

  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :project_id,
      :path,
      :language,
      :size_bytes,
      :line_count,
      :last_modified,
      :last_indexed,
      :content_hash,
      :git_churn,
      :git_authors,
      :risk_score
    ])
    |> validate_required([:project_id, :path])
    |> unique_constraint([:project_id, :path])
  end
end
