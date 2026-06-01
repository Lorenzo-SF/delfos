defmodule Delfos.Factory do
  alias Delfos.{Repo, Schema}

  def build(:project, attrs \\ []) do
    %Schema.Project{
      name: attrs[:name] || "test_project",
      path: attrs[:path] || "/tmp/test_project_#{:rand.uniform(9999)}",
      primary_stack: attrs[:stack] || "elixir",
      all_stacks: ["elixir"]
    }
  end

  def build(:file, attrs \\ []) do
    %Schema.File{
      path: attrs[:path] || "lib/test.ex",
      language: "elixir",
      line_count: 100,
      content_hash: "abc123",
      project_id: attrs[:project_id]
    }
  end

  def build(:symbol, attrs \\ []) do
    %Schema.Symbol{
      name: attrs[:name] || "test_function",
      qualified_name: attrs[:qualified_name] || "TestModule.test_function",
      kind: attrs[:kind] || "function",
      language: "elixir",
      content: attrs[:content] || "def test_function, do: :ok",
      file_id: attrs[:file_id],
      project_id: attrs[:project_id]
    }
  end

  def insert!(kind, attrs \\ []) do
    build(kind, attrs) |> Repo.insert!()
  end
end
