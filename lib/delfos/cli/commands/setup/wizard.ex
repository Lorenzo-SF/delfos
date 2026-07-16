defmodule Delfos.CLI.Commands.Setup.Wizard do
  @moduledoc """
  Thin wrapper around `Alaja.Wizard` for the LLM / DB setup wizards.

  Provides the three pieces that all the existing sub-wizards
  (script/ollama/external/llama_cpp) hand-roll today, so we have a
  single visual identity across `delfos config setup llm`:

    * `welcome/3`       — coloured Header banner (was Alaja.Components.Header)
    * `ask/3`           — numbered prompt with optional hint
    * `confirm_summary/1` — Box with the answers before persisting

  This is intentionally a *Delfos-side* wrapper, not a new
  `Alaja.Components.Wizard`. The Alaja.Wizard module already exists
  for declarative form rendering, but it's not interactive — it
  doesn't walk the user through questions. The setup wizards need
  interactive flow (questions with hints, with defaults, with skip
  handling), so we keep the orchestration in Delfos where the
  prompts live.

  ## Usage

      Wizard.welcome("LLM setup", "Pick your engine",
                     subtitle_color: {0, 180, 216})

      {:ok, url} = Wizard.ask("Ollama URL",
                              default: "http://localhost:11434",
                              hint: "Press Enter to accept default")

      case Wizard.confirm_summary([
             {"URL", url},
             {"Model", "llama3"}
           ]) do
        :yes -> persist(url)
        :no  -> cancel()
      end
  """

  alias Alaja
  alias Alaja.Components.{Box, Header}

  @default_accent {0, 180, 216}

  @doc """
  Renders the welcome header for a wizard. Standardises the banner
  across the setup subcommands.
  """
  @spec welcome(String.t(), String.t(), keyword()) :: :ok
  def welcome(title, subtitle, opts \\ []) do
    Alaja.print_raw("\n")

    Header.print(title,
      subtitle: subtitle,
      size: :small,
      color: Keyword.get(opts, :subtitle_color, @default_accent)
    )

    Alaja.print_raw("\n")
  end

  @doc """
  Prompts the user for a single value. Returns `{:ok, value}`,
  `:skip`, or `:error` (non-interactive stdin).

  ## Options

    * `:default`  — value returned when the user hits Enter
    * `:hint`     — printed beneath the prompt (small, dim)
    * `:index`    — when given, the prompt is rendered as "{index}. {label}"
                    for step-by-step wizards
    * `:choices`  — list of `{label, value}` tuples; when given, prompts
                    via `Interactive.question_with_options/3` instead of
                    free-form text. Returns `:skip` for the special
                    :skip choice.
    * `:color`    — Alaja color for the prompt (default :cyan)
  """
  @spec ask(String.t(), keyword()) :: {:ok, term()} | :skip | :error
  def ask(label, opts \\ []) do
    prompt_text = render_prompt_text(label, opts)
    print_hint(opts[:hint])

    cond do
      is_list(opts[:choices]) ->
        ask_with_choices(prompt_text, opts)

      true ->
        ask_freeform(prompt_text, opts)
    end
  end

  @doc """
  Asks the user to confirm a Box-rendered summary of the answers
  before persisting. Returns `:yes`, `:no`, or `:error`.

  `pairs` is a list of `{label, value}` tuples. The Box is rendered
  via `Alaja.Components.Box` with title "Confirm setup".
  """
  @spec confirm_summary([{String.t(), term()}]) :: :yes | :no | :error
  def confirm_summary(pairs) do
    body =
      Enum.map_join(pairs, "\n", fn {label, value} ->
        "  #{label}: #{value}"
      end)

    Box.print(body, title: "Confirm setup", border: :rounded, padding: 1)

    Alaja.Printer.Interactive.question_with_options(
      "Save this configuration?",
      [{"Yes, save", :yes}, {"No, cancel", :no}],
      color: :cyan,
      default: 1
    )
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp render_prompt_text(label, opts) do
    prefix =
      case opts[:index] do
        nil -> ""
        i when is_integer(i) -> "#{i}. "
        _ -> ""
      end

    default_suffix =
      case opts[:default] do
        nil -> ""
        "" -> ""
        d -> " [#{d}]"
      end

    "#{prefix}#{label}#{default_suffix}:"
  end

  defp print_hint(nil), do: :ok

  defp print_hint(hint) when is_binary(hint) and hint != "" do
    Alaja.print_raw("     #{Alaja.ANSI.dim()}#{hint}#{Alaja.ANSI.reset()}\n")
  end

  defp ask_freeform(prompt_text, opts) do
    color = Keyword.get(opts, :color, :cyan)
    raw = Alaja.Printer.Interactive.question(prompt_text, color: color)

    cond do
      is_nil(raw) ->
        :error

      raw == "" and not is_nil(opts[:default]) ->
        {:ok, opts[:default]}

      raw == "" ->
        :skip

      true ->
        {:ok, String.trim_trailing(raw, "/")}
    end
  end

  defp ask_with_choices(prompt_text, opts) do
    color = Keyword.get(opts, :color, :cyan)
    default = opts[:default_index] || 1

    case Alaja.Printer.Interactive.question_with_options(prompt_text, opts[:choices],
           color: color,
           default: default
         ) do
      :skip -> :skip
      :error -> :error
      choice -> {:ok, choice}
    end
  end
end
