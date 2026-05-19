defmodule Delfos.CLI.Commands.Scan do
  @moduledoc "Re-escanea el proyecto (incremental por defecto)."

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.Indexer.Scanner

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [full: :boolean, path: :string])
    full = opts[:full] || false

    project =
      case opts[:path] do
        nil ->
          Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

        path ->
          Repo.get_by(Schema.Project, path: Path.expand(path))
      end

    unless project do
      IO.puts("No hay proyectos. Usa delfos init")
      System.halt(1)
    end

    IO.puts("Escaneando #{project.name} (#{if full, do: "completo", else: "incremental"})...")

    case Scanner.scan(project, full: full) do
      {:ok, %{processed: ok, errors: err}} ->
        IO.puts("Completado: #{ok} archivos, #{err} errores")

        if err > 0 do
          IO.puts("⚠️  Algunos archivos fallaron. Ejecuta: delfos doctor")
        end

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end
end
