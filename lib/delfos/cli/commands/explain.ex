defmodule Delfos.CLI.Commands.Explain do
  @moduledoc """
  Explain a specific symbol with framework context, using the LLM model.

  All output is rendered through `Alaja` for consistent icon-prefixed
  messages.
  """

  import Ecto.Query
  alias Alaja
  alias Alaja.Components.{Box, Separator}
  alias Delfos.{Repo, Schema}
  alias Delfos.CLI.Errors
  alias Delfos.LLM.{Client, FrameworkContext}
  alias Delfos.Syntax.Utils, as: SyntaxUtils

  @help """
  USAGE
      delfos explain <name> [flags]

  Explain a symbol with framework context, using the LLM model.

  ARGUMENTS
      name           Partial or full symbol name (function, module, etc.)

  FLAGS
      --fresh        Force regeneration via LLM (skip cached summary)

  EXAMPLES
      delfos explain UserController.create
      delfos explain "authenticate"
      delfos explain MyModule.fun/2 --fresh
      delfos explain MyModule.fun/2 --llm-less  # static info only
  """

  @doc "Returns the help block. Used by `Delfos.CLI` to render `--help`."
  def help_text, do: @help

  def run_with_opts(%{help: true}) do
    Alaja.print_raw(help_text())
  end

  def run_with_opts(opts) do
    target = Map.get(opts, :name, "")
    force_fresh = Map.get(opts, :fresh, false) == true
    llm_less? = Map.get(opts, :llm_less, false) == true

    project = Repo.one(from(p in Schema.Project, order_by: [desc: p.last_scanned], limit: 1))

    unless project do
      Errors.abort(
        ["delfos", "explain"],
        "No projects registered.",
        hint: "Run: delfos init ."
      )
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
      Errors.abort(
        ["delfos", "explain"],
        "Symbol not found: #{target}",
        hint: "Try a partial name (e.g. just the function suffix)"
      )
    end

    Alaja.print_info("Explaining: #{symbol.qualified_name} (#{symbol.kind})")
    Alaja.print_raw("\n")

    # Render symbol source with syntax highlighting if content is available.
    # We try highlighting, but fall back to plain text if anything goes wrong
    # (the Elixir tokenizer can produce ANSI sequences that some terminals
    # reject when the source contains certain Unicode characters; better
    # to show plain code than crash the whole command).
    #
    # v2.5.0 (UX5): wrap the source in an Alaja.Components.Box titled
    # "Source" so it's visually distinct from the explanation text and
    # the metadata block below.
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

      source_text =
        cond do
          is_binary(rendered) and rendered != "" ->
            rendered

          true ->
            # Build a plain markdown-fenced code block that the Box
            # can render without losing width.
            "```#{symbol.language || ""}\n#{content}\n```"
        end

      # Print the source as a single box. Syntax-highlighted output
      # contains its own ANSI colour escapes; Box handles them.
      Box.print(source_text,
        title: "Source — #{symbol.qualified_name}",
        border: :rounded,
        padding: 1
      )

      Alaja.print_raw("\n")
    end

    # If there's a cached summary and --fresh isn't requested, show it directly.
    # `--llm-less` skips the LLM call entirely (B7) — even when no cached
    # summary is available, we show "(no summary)" rather than calling.
    cond do
      symbol.summary && not force_fresh ->
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

      llm_less? ->
        Alaja.print_warning(
          "(LLM skipped — no cached summary; run `delfos summarize` to populate)"
        )

      true ->
        generate_explanation(symbol)
    end

    # Static context (callers/callees/metrics/related chunks). This
    # absorbs the legacy `delfos agents --symbol <name>` flow removed
    # in v2.3.0 — see docs/REFACTOR_PLAN.md §3.8.
    print_symbol_context(symbol)
  end

  # Print callers / callees / file metrics / semantically related
  # chunks for a symbol. Cheap DB queries; no LLM call.
  #
  # v2.5.0 (UX5): wrap the whole context block in a Box titled
  # "Metadata" and use Separator to divide sub-sections visually.
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

    # Build the metadata block as one Buffer/string then wrap in a Box.
    sep =
      Separator.render(nil, width: 60, color: {80, 80, 80})
      |> Alaja.Buffer.to_iodata()
      |> IO.iodata_to_binary()

    sections =
      [
        "Callers (#{length(callers)}):",
        render_relationship_lines(callers),
        sep,
        "Callees (#{length(callees)}):",
        render_relationship_lines(callees),
        sep,
        render_metrics_lines(metrics),
        sep,
        "Semantically related chunks:",
        render_related_chunks_lines(related_chunks)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    Alaja.print_raw("\n")

    Box.print(sections,
      title: "Metadata — #{symbol.qualified_name}",
      border: :rounded,
      padding: 1
    )
  end

  defp render_relationship_lines([]), do: "  (ninguno)"

  defp render_relationship_lines(items) do
    Enum.map_join(items, "\n", fn %{name: name, kind: kind} ->
      "  - `#{name}` (#{kind})"
    end)
  end

  defp render_metrics_lines(nil), do: "Métricas del archivo:\n  (sin métricas)"

  defp render_metrics_lines(m) do
    in_cycle = if m.in_cycle, do: "⚠️ SÍ", else: "no"

    """
    Métricas del archivo:
      Afferent coupling: #{m.afferent_coupling}
      Efferent coupling: #{m.efferent_coupling}
      Instability:        #{Float.round(m.instability || 0.0, 2)}
      Debt score:         #{Float.round(m.debt_score || 0.0, 1)}
      En ciclo:           #{in_cycle}
    """
  end

  defp render_related_chunks_lines([]), do: "  (ninguno)"

  defp render_related_chunks_lines(chunks) do
    Enum.map_join(chunks, "\n", fn chunk ->
      preview = String.slice(chunk[:content] || "", 0, 200)
      "  ```\n  #{preview}\n  ```"
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

    # explain uses the single LLM endpoint configured via `[llm]`.
    opts = [use_case: :explain]

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
        Errors.print_error(
          "LLM server is not available.",
          hint: "Start it with: llama-run gpt-oss  (or use the cached summary with: delfos explain #{symbol.name})"
        )

      {:error, reason} ->
        Errors.print_error("LLM call failed: #{inspect(reason)}",
          hint: "Run `delfos doctor` to diagnose the LLM gateway"
        )
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
end
