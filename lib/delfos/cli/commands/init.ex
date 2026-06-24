defmodule Delfos.CLI.Commands.Init do
  @moduledoc "Registra un proyecto y realiza el primer scan completo."

  alias Delfos.{Repo, Schema}

  def run(args) do
    path = List.first(args) || File.cwd!()
    path = Path.expand(path)

    unless File.dir?(path) do
      IO.puts("Error: #{path} no existe o no es un directorio")
      System.halt(1)
    end

    name = Path.basename(path)
    primary_stack = detect_primary_stack(path)
    all_stacks = detect_all_stacks(path)
    git_info = read_git_info(path)

    IO.puts("Inicializando: #{name}")
    IO.puts("  Stack: #{primary_stack} | Stacks: #{Enum.join(all_stacks, ", ")}")
    IO.puts("  Git: #{git_info[:branch] || "—"} @ #{git_info[:commit] || "—"}")

    project =
      case Repo.get_by(Schema.Project, path: path) do
        nil ->
          Repo.insert!(
            Schema.Project.changeset(%Schema.Project{}, %{
              name: name,
              path: path,
              primary_stack: primary_stack,
              all_stacks: all_stacks,
              git_remote: git_info[:remote],
              git_branch: git_info[:branch],
              last_commit: git_info[:commit]
            })
          )

        existing ->
          IO.puts("  Proyecto ya existe — actualizando metadatos")

          Repo.update!(
            Schema.Project.changeset(existing, %{
              primary_stack: primary_stack,
              all_stacks: all_stacks,
              git_remote: git_info[:remote],
              git_branch: git_info[:branch],
              last_commit: git_info[:commit]
            })
          )
      end

    IO.puts("\nScan completo iniciando...")
    Delfos.CLI.Commands.Scan.run(["--full"])

    IO.puts("""

    ✓ #{name} indexado. Próximos pasos:
      delfos summarize          # generar resúmenes LLM
      delfos integrate all --yes # configurar agentes IA
      delfos serve --mcp &      # arrancar servidor MCP
      delfos query "..."        # buscar en el índice
    """)
  end

  defp detect_primary_stack(path) do
    cond do
      File.exists?("#{path}/mix.exs") -> "elixir"
      File.exists?("#{path}/Cargo.toml") -> "rust"
      File.exists?("#{path}/go.mod") -> "go"
      File.exists?("#{path}/pyproject.toml") or File.exists?("#{path}/setup.py") -> "python"
      File.exists?("#{path}/package.json") -> "node"
      File.exists?("#{path}/pom.xml") or File.exists?("#{path}/build.gradle") -> "java"
      File.exists?("#{path}/pubspec.yaml") -> "dart"
      File.exists?("#{path}/Gemfile") -> "ruby"
      File.exists?("#{path}/composer.json") -> "php"
      true -> "unknown"
    end
  end

  defp detect_all_stacks(path) do
    [
      {"elixir", "mix.exs"},
      {"rust", "Cargo.toml"},
      {"go", "go.mod"},
      {"python", "pyproject.toml"},
      {"node", "package.json"},
      {"java", "pom.xml"},
      {"dart", "pubspec.yaml"},
      {"ruby", "Gemfile"},
      {"php", "composer.json"}
    ]
    |> Enum.filter(fn {_, f} -> File.exists?("#{path}/#{f}") end)
    |> Enum.map(fn {s, _} -> s end)
    |> case do
      [] -> ["unknown"]
      s -> s
    end
  end

  # A-12 audit fix: timeout 5s para git queries durante init (son reads locales rápidos).
  @git_info_timeout 5_000

  defp read_git_info(path) do
    git = fn args ->
      task = Task.async(fn -> System.cmd("git", ["-C", path | args], stderr_to_stdout: true) end)

      case Task.yield(task, @git_info_timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {out, 0}} -> String.trim(out)
        _ -> nil
      end
    end

    %{
      remote: git.(["remote", "get-url", "origin"]),
      branch: git.(["rev-parse", "--abbrev-ref", "HEAD"]),
      commit: git.(["rev-parse", "--short", "HEAD"])
    }
  end
end
