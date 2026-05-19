defmodule Delfos.Schema.Project do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "projects" do
    field(:name, :string)
    field(:path, :string)
    field(:primary_stack, :string)
    field(:all_stacks, {:array, :string}, default: [])
    field(:git_remote, :string)
    field(:git_branch, :string)
    field(:last_commit, :string)
    field(:last_scanned, :utc_datetime)
    field(:config, :map, default: %{})
    has_many(:files, Delfos.Schema.File)
    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :path,
      :primary_stack,
      :all_stacks,
      :git_remote,
      :git_branch,
      :last_commit,
      :last_scanned,
      :config
    ])
    |> validate_required([:name, :path])
    |> unique_constraint(:path)
  end
end
