defmodule Delfos.Schema.Summary do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "summaries" do
    field(:level, :integer)
    field(:scope, :string)
    field(:content, :string)
    field(:content_hash, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:model_used, :string)
    field(:generated_at, :utc_datetime)

    belongs_to(:project, Delfos.Schema.Project)
    belongs_to(:file, Delfos.Schema.File)
    belongs_to(:symbol, Delfos.Schema.Symbol)

    timestamps(type: :utc_datetime)
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :project_id,
      :file_id,
      :symbol_id,
      :level,
      :scope,
      :content,
      :content_hash,
      :embedding,
      :model_used,
      :generated_at
    ])
    |> validate_required([:project_id, :level, :scope, :content])
    |> unique_constraint([:project_id, :level, :scope])
  end
end
