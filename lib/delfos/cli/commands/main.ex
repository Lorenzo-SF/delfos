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

      ["version" | _] ->
        IO.puts("Delfos v#{Delfos.version()}")

      ["help" | _] ->
        print_help()

      [] ->
        print_help()

      [cmd | _] ->
        IO.puts("Comando desconocido: #{cmd}\n")
        print_help()
    end
  end

  defp print_help do
    IO.puts("""

    Delfos v#{Delfos.version()} — Base de conocimiento para proyectos de software

    USO
      delfos <comando> [opciones]

    COMANDOS PRINCIPALES
      init [ruta]          Registrar proyecto y hacer el primer scan completo
      scan                 Re-escanear (incremental por defecto, --full para completo)
      query <texto>        Búsqueda híbrida (vector + BM25 + grafo)
                           Opciones: --kind function|module|class
                                     --level summary|symbol|chunk
                                     -n <top_n>  --format json

    ANÁLISIS
      audit                Deuda técnica: hotspots, ciclos, FIXME/HACK/DEBT
      summarize            Generar/actualizar resúmenes LLM jerárquicos
                           Opciones: --level 3|4
      explain <nombre>     Explicación LLM de un símbolo concreto

    GRAFO
      graph callers <nombre>   Qué símbolos llaman a <nombre>
      graph callees <nombre>   Qué símbolos llama <nombre>
      graph impact  <nombre>   Análisis de impacto BFS
      graph cycles             Archivos en ciclos de dependencia

    CONTEXTO PARA AGENTES
      context              Generar AGENTS.md y CLAUDE.md ricos
                           Opciones: --output <dir>  --symbol <nombre>  --format markdown
      context --symbol <nombre>  Contexto dinámico centrado en un símbolo

    DIAGNÓSTICO
      doctor               Verificar DB, pgvector, servidores embed/LLM
      status               Estado del índice y proyectos registrados
      version              Versión instalada

    EJEMPLOS
      delfos init .
      delfos query "cómo se autentica un usuario"
      delfos query "validación de formularios" --level summary
      delfos graph impact UserController
      delfos context --symbol AuthPlug
      delfos audit
    """)
  end
end
