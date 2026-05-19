defmodule Delfos.CLI.Commands.Summarize do
  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.LLM.Client

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [level: :integer])
    max_level = opts[:level] || 3

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project,
      do:
        (
          IO.puts("No hay proyectos. Usa delfos init")
          System.halt(1)
        )

    IO.puts("Generando resúmenes hasta nivel #{max_level}...")

    # L4: resúmenes de símbolos (funciones/clases)
    if max_level >= 4, do: summarize_symbols(project)

    # L3: resúmenes de archivos
    if max_level >= 3, do: summarize_files(project)

    IO.puts("Resúmenes generados.")
  end

  defp summarize_symbols(project) do
    IO.puts("L4: resumiendo símbolos...")

    symbols =
      Repo.all(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id and is_nil(s.summary),
          where: s.kind in ["function", "module", "class"],
          limit: 50
        )
      )

    Enum.each(symbols, fn symbol ->
      messages = [
        %{
          role: "user",
          content: """
            Resume en 2-3 frases este #{symbol.kind} de #{symbol.language}:
            ```
            #{String.slice(symbol.content || "", 0, 800)}
            ```
            Qué hace, parámetros relevantes y efectos secundarios. Solo el resumen, sin formato.
          """
        }
      ]

      case Client.chat(messages, reasoning: "low", max_tokens: 150) do
        {:ok, summary} ->
          symbol
          |> Schema.Symbol.changeset(%{
            summary: summary,
            summary_hash: symbol.content && :crypto.hash(:md5, symbol.content) |> Base.encode16()
          })
          |> Repo.update()

        _ ->
          :ok
      end
    end)
  end

  defp summarize_files(project) do
    IO.puts("L3: resumiendo archivos...")

    files =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id,
          limit: 30
        )
      )

    Enum.each(files, fn file ->
      existing = Repo.get_by(Schema.Summary, project_id: project.id, level: 3, scope: file.path)

      if is_nil(existing) do
        symbols_text =
          Repo.all(
            from(s in Schema.Symbol,
              where: s.file_id == ^file.id,
              select: fragment("? || ' ' || ?", s.kind, s.name)
            )
          )
          |> Enum.join(", ")

        messages = [
          %{
            role: "user",
            content: """
              Resume el archivo #{file.path} (#{file.language}) que contiene: #{symbols_text}.
              2-3 frases: responsabilidad principal, dependencias clave y efectos secundarios.
            """
          }
        ]

        case Client.chat(messages, reasoning: "low", max_tokens: 200) do
          {:ok, content} ->
            Repo.insert!(
              Schema.Summary.changeset(%Schema.Summary{}, %{
                project_id: project.id,
                level: 3,
                scope: file.path,
                file_id: file.id,
                content: content,
                model_used: Application.get_env(:delfos, :llm)[:model],
                generated_at: DateTime.utc_now()
              })
            )

          _ ->
            :ok
        end
      end
    end)
  end
end
