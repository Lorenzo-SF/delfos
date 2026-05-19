defmodule Delfos.CLI.Commands.Scan do
  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.Indexer.Scanner

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [full: :boolean])
    full = opts[:full] || false

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project,
      do:
        (
          IO.puts("No hay proyectos. Usa delfos init")
          System.halt(1)
        )

    IO.puts("Escaneando #{project.name} (#{if full, do: "completo", else: "incremental"})...")

    case Scanner.scan(project, full: full) do
      {:ok, %{processed: ok, errors: err}} ->
        IO.puts("Completado: #{ok} archivos, #{err} errores")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end
end
