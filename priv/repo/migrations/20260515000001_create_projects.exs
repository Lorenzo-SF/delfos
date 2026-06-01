defmodule Delfos.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    create table(:projects, primary_key: false) do
      add :id,            :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name,          :string, null: false
      add :path,          :string, null: false
      add :primary_stack, :string
      add :all_stacks,    {:array, :string}, default: []
      add :git_remote,    :string
      add :git_branch,    :string
      add :last_commit,   :string
      add :last_scanned,  :utc_datetime
      add :config,        :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:path])
  end

  def down, do: drop table(:projects)
end
