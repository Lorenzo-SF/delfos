defmodule Delfos.CLI.Commands.Explain do
  @moduledoc """
  Explain a specific symbol with framework context, using the thinker model.

  All output is rendered through `Alaja` for consistent icon-prefixed
  messages.
  """

  import Ecto.Query
  alias Alaja
  alias Alaja.Printer
  alias Delfos.{Repo, Schema}
  alias Delfos.LLM.{Client, FrameworkContext}
  alias Delfos.Syntax.Utils, as: SyntaxUtils

  @help """
  USAGE
      delfos explain <name> [flags]

  Explain a symbol with framework context, using the thinker model.

  ARGUMENTS
      name           Partial or full symbol name (function, module, etc.)

  FLAGS
      --fresh        Force regeneration via LLM (skip cached summary)

  EXAMPLES
      delfos explain UserController.create
      delfos explain "authenticate"
      delfos explain MyModule.fun/2 --fresh
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  def run_with_opts(%{help: true}) do
    Alaja.print_raw(help_text())
  end

  def run_with_opts(opts) do
    target = Map.get(opts, :name, "")
    force_fresh = Map.get(opts, :fresh, false) == true

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Alaja.print_error("No projects registered. Run: delfos init")
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
      Alaja.print_error("Not found: #{target}")
      System.halt(1)
    end

    Alaja.print_info("Explaining: #{symbol.qualified_name} (#{symbol.kind})")
    Alaja.print_raw("\n")

    # Render symbol source with syntax highlighting if content is available.
    # We try highlighting, but fall back to plain text if anything goes wrong
    # (the Elixir tokenizer can produce ANSI sequences that some terminals
    # reject when the source contains certain Unicode characters; better
    # to show plain code than crash the whole command).
    if symbol.content && symbol.content != "" do
      content =
        if String.length(symbol.content) > 4000,
          do: String.slice(symbol.content, 0, 4000) <> "... (truncated)",
          else: symbol.content

      rendered =
        try do
          Alaja.Syntax.highlight_ansi(content, safe_lang(symbol.language))
        rescue
          _ -> nil
        end

      if is_binary(rendered) and rendered != "" do
        try do
          Printer.print_raw(rendered)
          Printer.print_raw("\n")
        rescue
          _ -> print_plain_code(content, symbol.language)
        catch
          :exit, _ -> print_plain_code(content, symbol.language)
        end
      else
        print_plain_code(content, symbol.language)
      end
    end

    # If there's a cached summary and --fresh isn't requested, show it directly
    if symbol.summary && not force_fresh do
      Alaja.print_raw("## Summary (cached)\n\n")

      case Delfos.LLM.Response.normalize(symbol.summary) do
        nil -> Alaja.print_warning("(cached summary is empty or in an unrecognised shape)")
        text -> Alaja.print_raw(text)
      end

      if symbol.signature do
        Alaja.print_raw("\n## Signature\n")
        Alaja.print_raw(symbol.signature)
      end

      Alaja.print_info("\n(Use --fresh to regenerate via LLM)")
    else
      generate_explanation(symbol)
    end

    # Static context (callers/callees/metrics/related chunks). This
    # absorbs the legacy `delfos agents --symbol <name>` flow removed
    # in v2.3.0 — see docs/REFACTOR_PLAN.md §3.8.
    print_symbol_context(symbol)
  end

  # Print callers / callees / file metrics / semantically related
  # chunks for a symbol. Cheap DB queries; no LLM call.
  defp print_symbol_context(symbol) do
    callers =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.from_id,
          where: r.to_id == ^symbol.id,
          select: %{name: s.qualified_name, kind: s.kind}
        )
      )

    callees =
      Repo.all(
        from(r in Schema.Relationship,
          join: s in Schema.Symbol,
          on: s.id == r.to_id,
          where: r.from_id == ^symbol.id,
          select: %{name: s.qualified_name, kind: s.kind}
        )
      )

    metrics =
      if symbol.file_id,
        do: Repo.get_by(Schema.FileMetrics, file_id: symbol.file_id),
        else: nil

    related_chunks =
      case Delfos.LLM.Client.embed(symbol.name) do
        {:ok, vec} ->
          try do
            Delfos.Retrieval.VectorSearch.search(symbol.project_id, vec, 5, nil, nil)
            |> Enum.reject(&(&1.id == symbol.id))
            |> Enum.take(3)
          rescue
            _ -> []
          end

        _ ->
          []
      end

    Alaja.print_raw("\n## Callers (quién llama a este símbolo)\n")
    print_relationship_list(callers)

    Alaja.print_raw("\n## Callees (qué llama este símbolo)\n")
    print_relationship_list(callees)

    Alaja.print_raw("\n## Métricas del archivo\n")
    print_metrics(metrics)

    Alaja.print_raw("\n## Chunks semánticamente relacionados\n")
    print_related_chunks(related_chunks)
  end

  defp print_relationship_list([]), do: Alaja.print_raw("  (ninguno)\n")

  defp print_relationship_list(items) do
    Enum.each(items, fn %{name: name, kind: kind} ->
      Alaja.print_raw("  - `#{name}` (#{kind})\n")
    end)
  end

  defp print_metrics(nil), do: Alaja.print_raw("  (sin métricas)\n")

  defp print_metrics(m) do
    Alaja.print_raw(
      "  - Afferent coupling: #{m.afferent_coupling}\n" <>
        "  - Efferent coupling: #{m.efferent_coupling}\n" <>
        "  - Instability:        #{Float.round(m.instability || 0.0, 2)}\n" <>
        "  - Debt score:        #{Float.round(m.debt_score || 0.0, 1)}\n" <>
        "  - En ciclo:           #{if m.in_cycle, do: "⚠️ SÍ", else: "no"}\n"
    )
  end

  defp print_related_chunks([]), do: Alaja.print_raw("  (ninguno)\n")

  defp print_related_chunks(chunks) do
    Enum.each(chunks, fn chunk ->
      preview = String.slice(chunk[:content] || "", 0, 200)
      Alaja.print_raw("  ```\n  #{preview}\n  ```\n")
    end)
  end

  defp generate_explanation(symbol) do
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

    # explain uses the thinker when available (higher quality)
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
        # Normalise via the shared module — see Delfos.LLM.Response.
        # Some LLM gateways (notably gpt-oss via the local
        # llama-server bridge) return the full response envelope
        # instead of just the text; this guards against
        # `String.Chars not implemented for Map` crashes.
        case Delfos.LLM.Response.normalize(explanation) do
          nil -> Alaja.print_warning("LLM returned empty explanation")
          text -> Alaja.print_raw(text)
        end

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        Alaja.print_error("LLM server is not available.")
        Alaja.print_info("Start it with: MODEL_ID=thinker bash llm-server.sh")
        Alaja.print_info("\nAlternatively, use the cached summary: delfos explain #{symbol.name}")

      {:error, reason} ->
        Alaja.print_error("Error: #{inspect(reason)}")
    end
  end

  @doc false
  defdelegate safe_to_atom(lang), to: SyntaxUtils

  defp safe_lang(lang) do
    case SyntaxUtils.safe_to_atom(lang) do
      nil -> :text
      atom -> atom
    end
  end

  defp print_plain_code(content, language) do
    lang_str =
      case language do
        nil -> ""
        "" -> ""
        l -> l
      end

    Printer.print_raw("```" <> lang_str <> "\n")
    Printer.print_raw(content)
    Printer.print_raw("\n```\n")
  end
end
