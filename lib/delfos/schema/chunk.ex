defmodule Delfos.Schema.Chunk do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chunks" do
    field(:content, :string)
    field(:line_start, :integer)
    field(:line_end, :integer)
    field(:chunk_index, :integer)
    field(:token_count, :integer)
    field(:embedding, Pgvector.Ecto.Vector)
    belongs_to(:symbol, Delfos.Schema.Symbol)
    belongs_to(:file, Delfos.Schema.File)
    belongs_to(:project, Delfos.Schema.Project)
    timestamps(type: :utc_datetime)
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :content,
      :line_start,
      :line_end,
      :chunk_index,
      :token_count,
      :embedding,
      :symbol_id,
      :file_id,
      :project_id
    ])
    |> validate_required([:content, :file_id, :project_id])
  end
end
