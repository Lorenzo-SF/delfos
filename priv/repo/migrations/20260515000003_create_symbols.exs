defmodule Delfos.Repo.Migrations.CreateSymbols do
  use Ecto.Migration

  def up do
    create table(:symbols, primary_key: false) do
      add :id,             :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :file_id,        references(:files,    type: :uuid, on_delete: :delete_all), null: false
      add :project_id,     references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :name,           :string, null: false
      add :qualified_name, :string
      add :kind,           :string, null: false
      add :visibility,     :string
      add :line_start,     :integer
      add :line_end,       :integer
      add :signature,      :text
      add :docstring,      :text
      add :content,        :text
      add :language,       :string
      add :metadata,       :map, default: %{}
      add :embedding,      :vector, size: 1024
      add :summary,        :text
      add :summary_hash,   :string
      timestamps(type: :utc_datetime)
    end

    create index(:symbols, [:project_id, :kind])
    create index(:symbols, [:file_id])
    create index(:symbols, [:project_id, :qualified_name])

    execute """
      CREATE INDEX symbols_embedding_idx ON symbols
      USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    """

    execute """
      CREATE INDEX symbols_fts_idx ON symbols
      USING gin(to_tsvector('simple',
        coalesce(name,'') || ' ' || coalesce(qualified_name,'') || ' ' || coalesce(content,'')))
    """
  end

  def down, do: drop table(:symbols)
end
