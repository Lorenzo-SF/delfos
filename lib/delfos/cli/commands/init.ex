defmodule Delfos.CLI.Commands.Init do
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
    stack = detect_stack(path)

    IO.puts("Inicializando Delfos para: #{name} (#{stack})")
    IO.puts("Ruta: #{path}")

    project =
      case Repo.get_by(Schema.Project, path: path) do
        nil ->
          IO.puts("Creando nuevo proyecto...")

          Repo.insert!(
            Schema.Project.changeset(%Schema.Project{}, %{
              name: name,
              path: path,
              primary_stack: stack,
              all_stacks: [stack]
            })
          )

        existing ->
          IO.puts("Proyecto ya existente, actualizando...")
          existing
      end

    IO.puts("Iniciando scan completo (puede tardar varios minutos)...")

    try do
      case Scanner.scan(project, full: true) do
        {:ok, %{processed: ok, errors: err}} ->
          IO.puts("Scan completado: #{ok} archivos procesados, #{err} errores")
          IO.puts("\nListo. Prueba: delfos query \"tu búsqueda\"")
      end
    rescue
      e ->
        IO.puts("Error en el scan: #{inspect(e)}")
    end
  end

  defp detect_stack(path) do
    cond do
      File.exists?("#{path}/mix.exs") -> "elixir"
      File.exists?("#{path}/Cargo.toml") -> "rust"
      File.exists?("#{path}/package.json") -> "node"
      File.exists?("#{path}/go.mod") -> "go"
      File.exists?("#{path}/pyproject.toml") -> "python"
      true -> "unknown"
    end
  end
end
