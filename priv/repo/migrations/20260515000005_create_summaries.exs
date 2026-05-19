defmodule Delfos.Repo.Migrations.CreateSummaries do
  use Ecto.Migration

  def up do
    create table(:summaries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :level, :integer, null: false
      add :scope, :string, null: false
      add :file_id, references(:files, type: :uuid, on_delete: :nilify_all)
      add :symbol_id, references(:symbols, type: :uuid, on_delete: :nilify_all)
      add :content, :text, null: false
      add :content_hash, :string
      # 1024 dimensiones para mxbai-embed-large-v1 (era 768 — incorrecto)
      add :embedding, :vector, size: 1024
      add :model_used, :string
      add :generated_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:summaries, [:project_id, :level, :scope])

    execute """
      CREATE INDEX summaries_embedding_idx ON summaries
      USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    """
  end

  def down, do: drop table(:summaries)
end
