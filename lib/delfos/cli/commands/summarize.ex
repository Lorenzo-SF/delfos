defmodule Delfos.CLI.Commands.Summarize do

  alias Alaja
  @moduledoc """
  Genera resúmenes LLM jerárquicos con contexto de framework.

  Niveles:
  - L4 (símbolos): resúmenes de funciones/módulos individuales.
  - L3 (archivos): resúmenes de archivo basados en sus símbolos.

  Usa el modelo rápido (Coder-3B por defecto) con max_tokens cortos.
  Inyecta contexto de framework en el prompt para mayor precisión.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.LLM.{Client, FrameworkContext}

  @batch_size 50

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [level: :integer, force: :boolean])
    max_level = opts[:level] || 3
    force = opts[:force] || false

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Alaja.print_info("No hay proyectos. Usa delfos init")
      System.halt(1)
    end

    Alaja.print_info("Generando resúmenes hasta nivel #{max_level}...")

    if max_level >= 4, do: summarize_symbols(project, force)
    if max_level >= 3, do: summarize_files(project, force)

    Alaja.print_info("Resúmenes generados.")
  end

  # ---------------------------------------------------------------------------
  # L4: Resúmenes de símbolos (con paginación y framework context)
  # ---------------------------------------------------------------------------

  defp summarize_symbols(project, force) do
    Alaja.print_info("L4: resumiendo símbolos...")
    summarize_symbols_page(project, force, 0, 0)
  end

  defp summarize_symbols_page(project, force, offset, total) do
    query =
      from(s in Schema.Symbol,
        where: s.project_id == ^project.id,
        where: s.kind in ["function", "module", "class", "macro", "struct", "trait", "interface"],
        order_by: s.id,
        limit: @batch_size,
        offset: ^offset
      )

    query = if force, do: query, else: where(query, [s], is_nil(s.summary))

    symbols = Repo.all(query)

    if Enum.empty?(symbols) do
      Alaja.print_info("  #{total} símbolos resumidos")
    else
      Enum.each(symbols, &summarize_symbol/1)
      summarize_symbols_page(project, force, offset + @batch_size, total + length(symbols))
    end
  end

  defp summarize_symbol(symbol) do
    framework_hint =
      FrameworkContext.for_symbol(
        symbol.language,
        symbol.metadata || %{},
        symbol.content
      )

    framework_str = if framework_hint, do: " #{framework_hint}", else: ""

    messages = [
      %{
        role: "user",
        content: """
        You are a senior software architect reviewing #{symbol.kind} `#{symbol.qualified_name}` \
        in a #{symbol.language} project#{framework_str}.

        Code:
        ```#{symbol.language}
        #{String.slice(symbol.content || "", 0, 1200)}
        ```

        Summarize in 2-3 sentences. Include:
        1. Core responsibility of this #{symbol.kind}
        2. Key inputs/outputs or return values
        3. Framework-specific lifecycle or side effects (if applicable)

        Be concise and technical. No markdown formatting. Same language as code comments.
        """
      }
    ]

    case Client.chat(messages, use_case: :summarize) do
      {:ok, summary} ->
        hash = symbol.content && :crypto.hash(:md5, symbol.content) |> Base.encode16()

        symbol
        |> Schema.Symbol.changeset(%{summary: String.trim(summary), summary_hash: hash})
        |> Repo.update()

      {:error, reason} ->
        require Logger
        Logger.debug("summarize_symbol falló para #{symbol.name}: #{inspect(reason)}")
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # L3: Resúmenes de archivos (con framework context y embedding)
  # ---------------------------------------------------------------------------

  defp summarize_files(project, force) do
    Alaja.print_info("L3: resumiendo archivos...")

    files =
      Repo.all(from(f in Schema.File, where: f.project_id == ^project.id, order_by: f.id))

    Enum.each(files, fn file ->
      existing =
        Repo.get_by(Schema.Summary, project_id: project.id, level: 3, scope: file.path)

      should_generate =
        force or is_nil(existing) or
          (existing.content_hash != nil and existing.content_hash != file.content_hash)

      if should_generate, do: generate_file_summary(file, project, existing)
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

    symbol_summaries =
      Repo.all(
        from(s in Schema.Symbol,
          where: s.file_id == ^file.id and not is_nil(s.summary),
          select: {s.name, s.summary},
          limit: 8
        )
      )
      |> Enum.map(fn {name, summ} -> "- #{name}: #{summ}" end)
      |> Enum.join("\n")

    framework_hint = FrameworkContext.for_symbol(file.language, %{}, "")
    framework_str = if framework_hint, do: " (#{framework_hint})", else: ""

    messages = [
      %{
        role: "user",
        content: """
        Summarize the file `#{file.path}`#{framework_str} which contains: #{symbols_text}.

        #{if symbol_summaries != "", do: "Symbol summaries:\n#{symbol_summaries}\n", else: ""}
        2-3 sentences: main responsibility, key dependencies, and side effects.
        Be technical and concise. No markdown.
        """
      }
    ]

    case Client.chat(messages, use_case: :summarize) do
      {:ok, content} ->
        embedding =
          case Client.embed(content) do
            {:ok, vec} -> vec
            _ -> nil
          end

        attrs = %{
          project_id: project.id,
          level: 3,
          scope: file.path,
          file_id: file.id,
          content: String.trim(content),
          content_hash: file.content_hash,
          embedding: embedding,
          model_used: Delfos.Config.Manager.llm()[:model],
          generated_at: DateTime.utc_now()
        }

        if existing do
          existing |> Schema.Summary.changeset(attrs) |> Repo.update()
        else
          Repo.insert!(Schema.Summary.changeset(%Schema.Summary{}, attrs))
        end

      _ ->
        :ok
    end
  end
end
