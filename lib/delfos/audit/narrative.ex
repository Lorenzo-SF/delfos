defmodule Delfos.Audit.Narrative do
  @moduledoc """
  Generates an LLM-powered narrative diagnosis of a project's technical
  debt (used by `delfos audit --with-explanation`).

  Falls back to a deterministic narrative if the LLM is unavailable.
  """

  alias Delfos.LLM.Client

  @doc """
  Returns a 1-2 paragraph narrative diagnosis of the audit results.

  Falls back to a structured template when:
    * the LLM endpoint is unreachable,
    * the LLM returns empty/invalid content,
    * `--llm-less` mode is active.
  """
  @spec generate(map()) :: {:ok, String.t()} | {:error, term()}
  def generate(_audit) do
    # Always succeeds with a fallback. The LLM path is best-effort.
  end

  @spec generate(map(), keyword()) :: {:ok, String.t()}
  def generate(audit, opts) do
    if Keyword.get(opts, :llm_less, false) do
      {:ok, fallback(audit)}
    else
      prompt = build_prompt(audit)

      case Client.chat(prompt, use_case: :explain, max_tokens: 600) do
        {:ok, text} ->
          case Delfos.LLM.Response.normalize(text) do
            nil -> {:ok, fallback(audit)}
            normalized -> {:ok, normalized}
          end

        _error ->
          {:ok, fallback(audit)}
      end
    end
  end

  @doc "Returns the deterministic fallback narrative (no LLM call)."
  @spec fallback(map()) :: String.t()
  def fallback(%{hotspots: hotspots, cycles: cycles, debt: top_debt}) do
    """
    # Resumen ejecutivo (fallback determinístico, sin LLM)

    El proyecto presenta **#{length(cycles)} archivos en ciclos de dependencia** y
    **#{length(top_debt)} archivos con deuda técnica alta**.

    ## Hotspots principales

    #{Enum.map_join(hotspots, "\n", fn h -> "- `#{h.path}` (risk: #{h.risk}, churn: #{h.churn})" end)}

    ## Recomendaciones

    - Refactorizar ciclos de dependencia detectados.
    - Priorizar tests en hotspots con churn alto.
    - Revisar archivos con `debt_score > 5.0` antes de modificarlos.

    (Para un análisis narrativo generado por LLM, configura `delfos config set llm url ...`)
    """
  end

  defp build_prompt(audit) do
    summary = summarize_audit(audit)

    """
    You are a senior software architect reviewing the technical debt of a
    project. Based on the following audit summary, produce a 1-2 paragraph
    executive diagnosis in the same language as the comments below. Be
    concise, actionable, and prioritize the top 3 issues.

    Audit summary:
    #{summary}

    Output: plain text, no markdown headers, no bullet points beyond what
    you absolutely need. Target: 120-180 words.
    """
  end

  defp summarize_audit(%{hotspots: hotspots, cycles: cycles, debt: top_debt}) do
    """
    Hotspots (#{length(hotspots)}):
    #{Enum.map_join(hotspots |> Enum.take(5), "\n", fn h -> "  - #{h.path}: risk=#{h.risk}, churn=#{h.churn}" end)}

    Files in cycles (#{length(cycles)}):
    #{Enum.map_join(cycles |> Enum.take(5), "\n", fn c -> "  - #{c.path}" end)}

    Top debt (#{length(top_debt)}):
    #{Enum.map_join(top_debt |> Enum.take(5), "\n", fn d -> "  - #{d.path}: debt=#{d.debt}, instability=#{d.instability}" end)}
    """
  end
end
