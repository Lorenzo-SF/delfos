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

      ["config" | rest] ->
        Commands.Config.run(rest)

      ["integrate" | rest] ->
        Commands.Integrate.run(rest)

      ["watch" | _] ->
        start_watch()

      ["serve", "--mcp"] ->
        Delfos.MCP.Server.start()

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

  # ---------------------------------------------------------------------------
  # Watch mode
  # ---------------------------------------------------------------------------

  defp start_watch do
    Application.put_env(:delfos, :watch, true)

    project = get_active_project()

    unless project do
      IO.puts("No hay proyectos. Ejecuta: delfos init .")
      System.halt(1)
    end

    IO.puts("Watching: #{project.path}")
    IO.puts("Re-indexando cambios automáticamente. Ctrl+C para salir.\n")

    # El Watcher ya arrancó en application.ex porque watch: true.
    # Solo necesitamos mantener el proceso vivo.
    Process.sleep(:infinity)
  end

  defp get_active_project do
    import Ecto.Query
    Delfos.Repo.one(from(p in Delfos.Schema.Project, order_by: [desc: p.last_scanned], limit: 1))
  rescue
    _ -> nil
  end

  # ---------------------------------------------------------------------------
  # Help
  # ---------------------------------------------------------------------------

  defp print_help do
    IO.puts("""

    Delfos v#{Delfos.version()} — Base de conocimiento semántico para proyectos de software

    USO
      delfos <comando> [opciones]

    INICIALIZACIÓN
      init [ruta]           Registrar proyecto y hacer el primer scan completo
      scan                  Re-escanear (incremental por defecto)
                            --full para re-indexar todo  --workers N (default: 4)

    BÚSQUEDA Y CONSULTA
      query <texto>         Búsqueda híbrida (vector + BM25 + grafo)
                            --kind function|module|class|struct|interface
                            --level summary|symbol|chunk
                            -n <N>   --format json
      explain <nombre>      Explicación LLM de un símbolo (--fresh para regenerar)

    ANÁLISIS
      audit                 Deuda técnica: hotspots, ciclos, inestabilidad
                            --file <ruta> para análisis de un archivo
      summarize             Generar resúmenes LLM  --level 3|4  --force

    GRAFO
      graph callers <nombre>   Qué llama a este símbolo  --depth N
      graph callees <nombre>   Qué llama este símbolo    --depth N
      graph impact  <nombre>   Impacto de cambiarlo      --depth N (default 3)
      graph cycles             Archivos en ciclos de dependencia

    CONTEXTO PARA AGENTES
      context                  AGENTS.md + CLAUDE.md del proyecto
                               --output <dir>  --symbol <nombre>

    CONFIGURACIÓN
      config show              Configuración activa
      config init              Crear ~/.config/delfos/delfos.conf
      config set <s> <k> <v>   Editar valor
      config get <s> <k>       Leer valor
      config preset <nombre>   local | anthropic | openai | openai-large

    INTEGRACIÓN CON AGENTES IA
      integrate [agente]       Configurar integración MCP
                               claude-code | opencode | cursor | aider | codex | zed | all
                               --yes para no preguntar
      serve --mcp              Servidor MCP stdio (con indexado en tiempo real)
      watch                    File watcher + re-indexado automático (modo CLI)

    DIAGNÓSTICO
      doctor [--fix]           Verifica DB, pgvector, servidores, NIF, cobertura
      status                   Estado del índice y proyectos registrados
      version                  Versión instalada

    EJEMPLOS
      delfos init .
      delfos config preset local
      delfos integrate all --yes
      delfos serve --mcp
      delfos query "autenticación JWT"
      delfos graph impact PaymentService --depth 5
      delfos explain UserController.create --fresh
      delfos audit --file lib/payments.ex
    """)
  end
end
