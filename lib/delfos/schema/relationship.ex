defmodule Delfos.Schema.Relationship do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @valid_kinds ~w(calls imports implements tests uses inherits references)
  schema "relationships" do
    field(:kind, :string)
    field(:weight, :float, default: 1.0)
    field(:metadata, :map, default: %{})
    belongs_to(:project, Delfos.Schema.Project)
    belongs_to(:from, Delfos.Schema.Symbol, foreign_key: :from_id)
    belongs_to(:to, Delfos.Schema.Symbol, foreign_key: :to_id)
    timestamps(type: :utc_datetime)
  end

  def changeset(rel, attrs) do
    rel
    |> cast(attrs, [:kind, :weight, :metadata, :project_id, :from_id, :to_id])
    |> validate_required([:kind, :project_id, :from_id, :to_id])
    |> validate_inclusion(:kind, @valid_kinds)
    |> unique_constraint([:from_id, :to_id, :kind])
  end
end
