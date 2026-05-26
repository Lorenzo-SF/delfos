defmodule Delfos.CLI.Commands.Explain do
  @moduledoc "Explica un símbolo concreto con contexto de framework, usando el modelo thinker."

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.LLM.{Client, FrameworkContext}

  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, switches: [fresh: :boolean])
    target = List.first(rest) || (IO.puts("Uso: delfos explain <nombre>") && System.halt(1))
    force_fresh = opts[:fresh] || false

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
          order_by: [asc: s.line_start],
          limit: 1
        )
      )

    unless symbol do
      IO.puts("No encontrado: #{target}")
      System.halt(1)
    end

    IO.puts("Explicando: #{symbol.qualified_name} (#{symbol.kind})\n")

    # Si hay resumen en caché y no se pide --fresh, mostrarlo directamente
    if symbol.summary and not force_fresh do
      IO.puts("## Resumen (caché)\n")
      IO.puts(symbol.summary)

      if symbol.signature do
        IO.puts("\n## Firma")
        IO.puts(symbol.signature)
      end

      IO.puts("\n(Usa --fresh para regenerar con el LLM)")
    else
      generate_explanation(symbol)
    end
  end

  defp generate_explanation(symbol) do
    framework_hint = FrameworkContext.for_symbol(
      symbol.language,
      symbol.metadata || %{},
      symbol.content
    )

    framework_str = if framework_hint, do: " #{framework_hint}", else: ""

    messages = [
      %{
        role: "user",
        content: """
        You are a senior software engineer. Explain this #{symbol.kind}#{framework_str}:

        Name: #{symbol.qualified_name}
        #{if symbol.signature, do: "Signature: #{symbol.signature}\n", else: ""}
        ```#{symbol.language}
        #{String.slice(symbol.content || "", 0, 2000)}
        ```

        Provide a clear technical explanation covering:
        1. What it does (core responsibility)
        2. Parameters and return value
        3. Side effects, errors it can raise, or edge cases
        4. How it fits in the broader architecture (based on its name/context)
        #{if framework_str != "", do: "5. Framework-specific behavior or lifecycle relevance", else: ""}

        Be precise and technical. Use the same language as the code comments.
        """
      }
    ]

    # explain usa el thinker si está disponible (mayor calidad)
    cfg = Delfos.Config.Manager.llm()
    opts = [use_case: :explain]

    opts =
      if cfg[:use_thinker_for_query] do
        Keyword.put(opts, :provider, cfg[:provider])
      else
        opts
      end

    case Client.chat(messages, opts) do
      {:ok, explanation} ->
        IO.puts(explanation)

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        IO.puts("Error: el servidor LLM no está disponible.")
        IO.puts("Arráncalo con: MODEL_ID=thinker bash llm-server.sh")
        IO.puts("\nAlternativamente, usa el resumen en caché: delfos explain #{symbol.name}")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end
end
