defmodule Delfos.Schema.Symbol do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "symbols" do
    field(:name, :string)
    field(:qualified_name, :string)
    field(:kind, :string)
    field(:visibility, :string)
    field(:line_start, :integer)
    field(:line_end, :integer)
    field(:signature, :string)
    field(:docstring, :string)
    field(:content, :string)
    field(:language, :string)
    field(:metadata, :map, default: %{})
    field(:embedding, Pgvector.Ecto.Vector)
    field(:summary, :string)
    field(:summary_hash, :string)
    belongs_to(:file, Delfos.Schema.File)
    belongs_to(:project, Delfos.Schema.Project)
    has_many(:chunks, Delfos.Schema.Chunk)
    timestamps(type: :utc_datetime)
  end

  @valid_kinds ~w(function module class endpoint test schema migration constant)
  def changeset(symbol, attrs) do
    symbol
    |> cast(attrs, [
      :name,
      :qualified_name,
      :kind,
      :visibility,
      :line_start,
      :line_end,
      :signature,
      :docstring,
      :content,
      :language,
      :metadata,
      :embedding,
      :summary,
      :summary_hash,
      :file_id,
      :project_id
    ])
    |> validate_required([:name, :kind, :file_id, :project_id])
    |> validate_inclusion(:kind, @valid_kinds)
  end
end
