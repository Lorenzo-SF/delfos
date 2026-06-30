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

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, switches: [fresh: :boolean])

    target =
      List.first(rest) ||
        (Alaja.print_error("Usage: delfos explain <name>") && System.halt(1))

    force_fresh = opts[:fresh] || false

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

    # Render symbol source with syntax highlighting if content is available
    if symbol.content && symbol.content != "" do
      lang = SyntaxUtils.safe_to_atom(symbol.language)

      content =
        if String.length(symbol.content) > 4000,
          do: String.slice(symbol.content, 0, 4000) <> "... (truncated)",
          else: symbol.content

      highlighted = Alaja.Syntax.highlight_ansi(content, lang)
      Printer.print_raw(highlighted)
      Printer.print_raw("\n")
    end

    # If there's a cached summary and --fresh isn't requested, show it directly
    if symbol.summary and not force_fresh do
      Alaja.print_raw("## Summary (cached)\n\n")
      Alaja.print_raw(symbol.summary)

      if symbol.signature do
        Alaja.print_raw("\n## Signature\n")
        Alaja.print_raw(symbol.signature)
      end

      Alaja.print_info("\n(Use --fresh to regenerate via LLM)")
    else
      generate_explanation(symbol)
    end
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
        Alaja.print_raw(explanation)

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
end
