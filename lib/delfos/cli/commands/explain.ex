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
    {opts, rest, _} = Alaja.CLI.OptionsParser.parse(args, %{switches: [fresh: :boolean]})

    target =
      List.first(rest) ||
        (Alaja.print_error("Usage: delfos explain <name>") && Delfos.CLI.halt(1))

    force_fresh = Keyword.get(opts, :fresh, false) == true

    project = Delfos.CLI.ProjectResolver.resolve(opts)

    unless project do
      Alaja.print_error("No projects registered. Run: delfos init")
      Delfos.CLI.halt(1)
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
      Delfos.CLI.halt(1)
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
