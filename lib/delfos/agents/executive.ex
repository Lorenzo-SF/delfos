defmodule Delfos.Agents.Executive do
  @moduledoc """
  Generates an LLM-powered executive summary that prepends the
  AGENTS.md / CLAUDE.md briefing (used by `delfos agents --with-explanation`).

  Falls back to a deterministic summary if the LLM is unavailable.
  """

  alias Delfos.LLM.Client

  @spec generate(map(), keyword()) :: {:ok, String.t()}
  def generate(%{name: name, files: files, symbols: symbols, cycles: cycles} = _ctx, opts) do
    if Keyword.get(opts, :llm_less, false) do
      {:ok, fallback(name, files, symbols, cycles)}
    else
      prompt = build_prompt(name, files, symbols, cycles)

      case Client.chat(prompt, use_case: :explain, max_tokens: 400) do
        {:ok, text} ->
          case Delfos.LLM.Response.normalize(text) do
            nil -> {:ok, fallback(name, files, symbols, cycles)}
            normalized -> {:ok, normalized}
          end

        _error ->
          {:ok, fallback(name, files, symbols, cycles)}
      end
    end
  end

  defp build_prompt(name, files, symbols, cycles) do
    """
    You are a senior software engineer writing an executive briefing
    for an AI coding agent that is about to work on the project `#{name}`.

    Stats:
      files indexed: #{files}
      symbols indexed: #{symbols}
      dependency cycles: #{cycles}

    Produce a 4-6 sentence executive summary covering: what kind of project
    this appears to be, what risks are visible from the cycle count, and
    the top priorities the agent should focus on first. Be concise,
    technical, and write in the same language as any code comments.
    """
  end

  defp fallback(name, files, symbols, cycles) do
    """
    > Resumen ejecutivo (fallback determinístico, sin LLM) — #{name}

    El proyecto `#{name}` tiene **#{files} archivos indexados** y **#{symbols} símbolos**.
    Se detectaron **#{cycles} archivos en ciclos de dependencia**. Estos ciclos son
    el principal indicador de complejidad arquitectónica — revisarlos antes
    de cualquier refactor mayor.
    """
  end
end
