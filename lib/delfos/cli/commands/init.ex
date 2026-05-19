defmodule Delfos.CLI.Commands.Init do
  @moduledoc "Registra un proyecto y realiza el primer scan completo."

  alias Delfos.{Repo, Schema}
  alias Delfos.Indexer.Scanner

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

    IO.puts("Inicializando Delfos para: #{name}")
    IO.puts("  Stack principal: #{primary_stack}")
    IO.puts("  Todos los stacks: #{Enum.join(all_stacks, ", ")}")
    IO.puts("  Ruta: #{path}")

    git_info = read_git_info(path)

    project =
      case Repo.get_by(Schema.Project, path: path) do
        nil ->
          IO.puts("Creando nuevo proyecto...")

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
          IO.puts("Proyecto ya existente, actualizando metadatos...")

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

    IO.puts("\nIniciando scan completo (puede tardar varios minutos)...")

    case Scanner.scan(project, full: true) do
      {:ok, %{processed: ok, errors: err}} ->
        IO.puts("Scan completado: #{ok} archivos procesados, #{err} errores")
        IO.puts("\nListo. Prueba:")
        IO.puts("  delfos query \"tu búsqueda\"")
        IO.puts("  delfos doctor")
        IO.puts("  delfos summarize")

      {:error, reason} ->
        IO.puts("Error en el scan: #{inspect(reason)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Detección de stacks
  # ---------------------------------------------------------------------------

  defp detect_primary_stack(path) do
    cond do
      File.exists?("#{path}/mix.exs") -> "elixir"
      File.exists?("#{path}/Cargo.toml") -> "rust"
      File.exists?("#{path}/go.mod") -> "go"
      File.exists?("#{path}/pyproject.toml") or File.exists?("#{path}/setup.py") -> "python"
      File.exists?("#{path}/package.json") -> "node"
      true -> "unknown"
    end
  end

  defp detect_all_stacks(path) do
    indicators = [
      {"elixir", "mix.exs"},
      {"rust", "Cargo.toml"},
      {"go", "go.mod"},
      {"python", "pyproject.toml"},
      {"python", "setup.py"},
      {"node", "package.json"}
    ]

    indicators
    |> Enum.filter(fn {_, file} -> File.exists?("#{path}/#{file}") end)
    |> Enum.map(fn {stack, _} -> stack end)
    |> Enum.uniq()
    |> case do
      [] -> ["unknown"]
      stacks -> stacks
    end
  end

  # ---------------------------------------------------------------------------
  # Info git
  # ---------------------------------------------------------------------------

  defp read_git_info(path) do
    remote =
      case System.cmd("git", ["-C", path, "remote", "get-url", "origin"], stderr_to_stdout: true) do
        {out, 0} -> String.trim(out)
        _ -> nil
      end

    branch =
      case System.cmd("git", ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"],
             stderr_to_stdout: true
           ) do
        {out, 0} -> String.trim(out)
        _ -> nil
      end

    commit =
      case System.cmd("git", ["-C", path, "rev-parse", "--short", "HEAD"],
             stderr_to_stdout: true
           ) do
        {out, 0} -> String.trim(out)
        _ -> nil
      end

    %{remote: remote, branch: branch, commit: commit}
  end
end
