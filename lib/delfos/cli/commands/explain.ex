defmodule Delfos.CLI.Commands.Explain do
  @moduledoc "Explica un símbolo concreto usando el LLM local."

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.LLM.Client

  def run(args) do
    target =
      List.first(args) ||
        (
          IO.puts("Uso: delfos explain <nombre_o_ruta>")
          System.halt(1)
        )

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      IO.puts("No hay proyectos. Usa delfos init")
      System.halt(1)
    end

    symbol =
      Repo.one(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id,
          where: ilike(s.name, ^"%#{target}%") or ilike(s.qualified_name, ^"%#{target}%"),
          limit: 1
        )
      )

    unless symbol do
      IO.puts("No encontrado: #{target}")
      System.halt(1)
    end

    IO.puts("Explicando: #{symbol.qualified_name} (#{symbol.kind})\n")

    # Si ya hay resumen LLM lo mostramos directamente sin gastar tokens
    if symbol.summary do
      IO.puts("## Resumen en caché\n")
      IO.puts(symbol.summary)
      IO.puts("\n## Firma\n#{symbol.signature || "(sin @spec)"}")
    else
      messages = [
        %{
          role: "user",
          content: """
            Explica este #{symbol.kind} de #{symbol.language}:

            ```#{symbol.language}
            #{String.slice(symbol.content || "", 0, 1500)}
            ```

            Incluye: qué hace, parámetros, valor de retorno, efectos secundarios y casos de uso.
            Sé conciso y técnico. Sin formato Markdown innecesario.
          """
        }
      ]

      case Client.chat(messages) do
        {:ok, explanation} -> IO.puts(explanation)
        {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
      end
    end
  end
end
