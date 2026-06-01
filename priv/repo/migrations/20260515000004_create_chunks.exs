defmodule Delfos.Repo.Migrations.CreateChunks do
  use Ecto.Migration

  def up do
    create table(:chunks, primary_key: false) do
      add :id,          :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :symbol_id,   references(:symbols,  type: :uuid, on_delete: :delete_all)
      add :file_id,     references(:files,    type: :uuid, on_delete: :delete_all), null: false
      add :project_id,  references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :content,     :text, null: false
      add :line_start,  :integer
      add :line_end,    :integer
      add :chunk_index, :integer
      add :token_count, :integer
      add :embedding,   :vector, size: 1024
      timestamps(type: :utc_datetime)
    end

    create index(:chunks, [:project_id])
    create index(:chunks, [:symbol_id])

    execute """
      CREATE INDEX chunks_embedding_idx ON chunks
      USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    """

    execute """
      CREATE INDEX chunks_fts_idx ON chunks
      USING gin(to_tsvector('simple', content))
    """
  end

  def down, do: drop table(:chunks)
end
