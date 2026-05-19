defmodule Delfos.CLI.Main do
  @moduledoc "Punto de entrada del CLI de Delfos."

  alias Delfos.CLI.Commands

  def main(args) do
    Application.ensure_all_started(:delfos)

    case args do
      ["init" | rest] ->
        Commands.Init.run(rest)

      ["scan" | rest] ->
        Commands.Scan.run(rest)

      ["query" | rest] ->
        Commands.Query.run(rest)

      ["audit" | rest] ->
        Commands.Audit.run(rest)

      ["summarize" | rest] ->
        Commands.Summarize.run(rest)

      ["explain" | rest] ->
        Commands.Explain.run(rest)

      ["graph" | rest] ->
        Commands.Graph.run(rest)

      ["context" | rest] ->
        Commands.Context.run(rest)

      ["doctor" | rest] ->
        Commands.Doctor.run(rest)

      ["status" | rest] ->
        Commands.Status.run(rest)

      ["help" | _] ->
        print_help()

      list when is_list(list) and length(list) == 0 ->
        print_help()

      [cmd | _] ->
        IO.puts("Comando desconocido: #{cmd}\n")
        print_help()
    end
  end

  defp print_help do
    IO.puts("""

    Delfos v#{Delfos.version()} — Base de conocimiento para proyectos de software

    Comandos:
      init         Registrar proyecto y hacer el primer scan
      scan         Re-escanear el proyecto (incremental por defecto)
      query        Búsqueda híbrida en el índice
      audit        Análisis de deuda técnica
      summarize    Generar/actualizar resúmenes jerárquicos
      explain      Explicar un archivo, módulo o función
      graph        Consultas al grafo de dependencias
      context      Generar AGENTS.md y CLAUDE.md
      doctor       Diagnóstico del índice
      status       Estado del servidor y del índice

    Usa `delfos <comando> --help` para más información.
    """)
  end
end
