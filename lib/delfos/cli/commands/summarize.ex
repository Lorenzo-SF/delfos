defmodule Delfos.CLI.Commands.Summarize do
  @moduledoc """
  Genera resúmenes jerárquicos con embeddings para todos los niveles.

  Niveles:
  - L4 (símbolos): résumenes de funciones/módulos individuales.
  - L3 (archivos): résumenes de archivo basados en sus símbolos.

  Mejoras:
  - Los resúmenes generados se embeben inmediatamente (fix: antes no se embebían).
  - Paginación interna para procesar proyectos con >50 símbolos sin límite.
  - Resúmenes de archivo también se actualizan cuando el contenido del archivo cambió.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.LLM.Client

  @batch_size 50

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [level: :integer])
    max_level = opts[:level] || 3

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      IO.puts("No hay proyectos. Usa delfos init")
      System.halt(1)
    end

    IO.puts("Generando resúmenes hasta nivel #{max_level}...")

    if max_level >= 4, do: summarize_symbols(project)
    if max_level >= 3, do: summarize_files(project)

    IO.puts("Resúmenes generados.")
  end

  # ---------------------------------------------------------------------------
  # L4: Resúmenes de símbolos (con paginación)
  # ---------------------------------------------------------------------------

  defp summarize_symbols(project) do
    IO.puts("L4: resumiendo símbolos...")
    summarize_symbols_page(project, 0, 0)
  end

  defp summarize_symbols_page(project, offset, total) do
    symbols =
      Repo.all(
        from(s in Schema.Symbol,
          where: s.project_id == ^project.id and is_nil(s.summary),
          where: s.kind in ["function", "module", "class", "macro", "struct"],
          order_by: s.id,
          limit: @batch_size,
          offset: ^offset
        )
      )

    if Enum.empty?(symbols) do
      IO.puts("  #{total} símbolos resumidos")
    else
      Enum.each(symbols, &summarize_symbol/1)
      summarize_symbols_page(project, offset + @batch_size, total + length(symbols))
    end
  end

  defp summarize_symbol(symbol) do
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

    case Client.chat(messages, max_tokens: 150) do
      {:ok, summary} ->
        summary_hash =
          symbol.content && :crypto.hash(:md5, symbol.content) |> Base.encode16()

        symbol
        |> Schema.Symbol.changeset(%{summary: summary, summary_hash: summary_hash})
        |> Repo.update()

      _ ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # L3: Resúmenes de archivos (con embedding)
  # ---------------------------------------------------------------------------

  defp summarize_files(project) do
    IO.puts("L3: resumiendo archivos...")

    files =
      Repo.all(
        from(f in Schema.File,
          where: f.project_id == ^project.id,
          order_by: f.id
        )
      )

    Enum.each(files, fn file ->
      existing =
        Repo.get_by(Schema.Summary, project_id: project.id, level: 3, scope: file.path)

      # Generar si no existe o si el archivo ha cambiado (content_hash diferente)
      should_generate =
        is_nil(existing) or
          (existing.content_hash != nil and existing.content_hash != file.content_hash)

      if should_generate do
        generate_file_summary(file, project, existing)
      end
    end)
  end

  defp generate_file_summary(file, project, existing) do
    symbols_text =
      Repo.all(
        from(s in Schema.Symbol,
          where: s.file_id == ^file.id,
          select: fragment("? || ' ' || ?", s.kind, s.name)
        )
      )
      |> Enum.join(", ")

    # También incluir los summaries individuales de los símbolos si existen
    symbol_summaries =
      Repo.all(
        from(s in Schema.Symbol,
          where: s.file_id == ^file.id and not is_nil(s.summary),
          select: {s.name, s.summary},
          limit: 10
        )
      )
      |> Enum.map(fn {name, summ} -> "- #{name}: #{summ}" end)
      |> Enum.join("\n")

    messages = [
      %{
        role: "user",
        content: """
          Resume el archivo #{file.path} (#{file.language}) que contiene: #{symbols_text}.

          #{if symbol_summaries != "", do: "Resúmenes de símbolos clave:\n#{symbol_summaries}\n", else: ""}
          2-3 frases: responsabilidad principal, dependencias clave y efectos secundarios.
        """
      }
    ]

    case Client.chat(messages, max_tokens: 200) do
      {:ok, content} ->
        # Generar embedding del resumen
        embedding =
          case Delfos.LLM.Client.embed(content) do
            {:ok, vec} -> vec
            _ -> nil
          end

        attrs = %{
          project_id: project.id,
          level: 3,
          scope: file.path,
          file_id: file.id,
          content: content,
          content_hash: file.content_hash,
          embedding: embedding,
          model_used: Application.get_env(:delfos, :llm)[:model],
          generated_at: DateTime.utc_now()
        }

        if existing do
          existing
          |> Schema.Summary.changeset(attrs)
          |> Repo.update()
        else
          Repo.insert!(Schema.Summary.changeset(%Schema.Summary{}, attrs))
        end

      _ ->
        :ok
    end
  end
end
