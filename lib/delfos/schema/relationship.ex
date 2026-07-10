defmodule Delfos.Schema.Relationship do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "relationships" do
    field(:kind, :string)
    field(:weight, :float, default: 1.0)
    field(:metadata, :map, default: %{})

    belongs_to(:project, Delfos.Schema.Project)
    belongs_to(:from, Delfos.Schema.Symbol, foreign_key: :from_id)
    belongs_to(:to, Delfos.Schema.Symbol, foreign_key: :to_id)
    belongs_to(:from_file, Delfos.Schema.File, foreign_key: :from_file_id)
    belongs_to(:to_file, Delfos.Schema.File, foreign_key: :to_file_id)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a relationship edge. Supports two flavours:

    * symbol-level: `kind = "imports"`, requires `from_id` and `to_id`.
    * file-level:   `kind = "imports_file"`, requires `from_file_id` and
      `to_file_id`.

  Exactly one of the from-side columns and one of the to-side columns
  must be set, matched by the kind. Custom validation below enforces
  this so we can't insert a row with both columns NULL or both set
  (which would violate the semantic model).
  """
  def changeset(rel, attrs) do
    rel
    |> cast(attrs, [
      :project_id,
      :from_id,
      :to_id,
      :from_file_id,
      :to_file_id,
      :kind,
      :weight,
      :metadata
    ])
    |> validate_required([:project_id, :kind])
    |> validate_from_to_pair(:from_id, :from_file_id, "from")
    |> validate_from_to_pair(:to_id, :to_file_id, "to")
    |> unique_constraint([:from_id, :to_id, :kind])
    |> unique_constraint([:from_file_id, :to_file_id, :kind])
  end

  # Exactly one of the two columns must be set. `kind` is the
  # discriminator: file-level rows must have file_id set; symbol-level
  # rows must have symbol id set.
  defp validate_from_to_pair(changeset, sym_field, file_field, side) do
    sym = get_field(changeset, sym_field)
    file = get_field(changeset, file_field)

    cond do
      is_nil(sym) and is_nil(file) ->
        add_error(
          changeset,
          sym_field,
          "#{side}-side: either #{sym_field} or #{file_field} is required"
        )

      not is_nil(sym) and not is_nil(file) ->
        add_error(
          changeset,
          sym_field,
          "#{side}-side: only one of #{sym_field} or #{file_field} can be set"
        )

      true ->
        changeset
    end
  end
end
