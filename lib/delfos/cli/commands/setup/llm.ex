defmodule Delfos.CLI.Commands.Setup.LLM do
  @moduledoc """
  Interactive LLM setup for Delfos.

  The entry point stays here, while provider-specific flows live in focused
  submodules under `Delfos.CLI.Commands.Setup.LLM.*`.
  """

  require Logger

  alias Alaja
  alias Alaja.Printer.Interactive
  alias Delfos.CLI.Commands.Setup.LLM.ChooseTarget
  alias Delfos.CLI.Commands.Setup.LLM.External
  alias Delfos.CLI.Commands.Setup.LLM.LlamaCpp
  alias Delfos.CLI.Commands.Setup.LLM.Ollama
  alias Delfos.CLI.Commands.Setup.Wizard
  alias Delfos.Config.Manager

  @providers [
    {"llama.cpp — GGUF files managed through Candil", :llama_cpp},
    {"Ollama — use a running Ollama daemon", :ollama},
    {"External API — OpenAI, Anthropic, or compatible", :external},
    {"Skip — I'll configure later", :skip}
  ]

  def run(opts \\ []) do
    opts = List.wrap(opts)
    force = Keyword.get(opts, :force, false) == true
    cfg = Manager.read()

    if configured?(cfg) and not force do
      handle_existing_config(opts)
    else
      start_wizard(opts)
    end
  rescue
    Jason.DecodeError ->
      Logger.warning("[setup llm] config parse error, starting wizard")
      start_wizard(List.wrap(opts))

    File.Error ->
      Logger.warning("[setup llm] config file error, starting wizard")
      start_wizard(List.wrap(opts))
  end

  @doc false
  def dispatch(:skip, _opts), do: skip_msg()

  def dispatch(target, opts) when target in [:llm, :embedding, :both] do
    choose_provider_and_run(target, opts)
  end

  def dispatch(_target, _opts) do
    Alaja.print_error("No valid LLM setup target")
    false
  end

  @doc false
  def scan_ggufs(dir), do: LlamaCpp.scan_ggufs(dir)

  @doc false
  def merge_and_write(updates) when is_map(updates) do
    Manager.read()
    |> deep_merge(updates)
    |> Manager.write()
  end

  defp handle_existing_config(opts) do
    llm = Manager.llm()
    embedding = Manager.embedding()

    Alaja.print_success("LLM: #{llm[:url]} · #{llm[:model]}")
    Alaja.print_success("Embedding: #{embedding[:url]} · dim=#{embedding[:dim]}")

    case Interactive.question_with_options(
           "LLM is already configured. What do you want to do?",
           [
             {"Keep current configuration", :keep},
             {"Re-configure LLM", :llm},
             {"Re-configure Embedding", :embedding},
             {"Re-configure Both", :both},
             {"Skip", :skip}
           ],
           color: :cyan,
           default: 1
         ) do
      :keep -> true
      :skip -> skip_msg()
      target when target in [:llm, :embedding, :both] -> dispatch(target, opts)
      :error -> true
    end
  end

  defp start_wizard(opts) do
    Wizard.welcome("LLM setup", "Choose how Delfos runs AI models")

    opts
    |> ChooseTarget.choose()
    |> dispatch(opts)
  end

  defp choose_provider_and_run(target, opts) do
    case provider_from_opts(opts) || ask_provider() do
      :llama_cpp ->
        LlamaCpp.run(%{target: target, force: Keyword.get(opts, :force, false) == true})

      :ollama ->
        Ollama.run(%{target: target, force: Keyword.get(opts, :force, false) == true})

      :external ->
        External.run(%{target: target, force: Keyword.get(opts, :force, false) == true})

      :skip ->
        skip_msg()

      :error ->
        false
    end
  end

  defp ask_provider do
    Interactive.question_with_options("Which engine / provider?", @providers,
      color: :cyan,
      default: 1
    )
  end

  defp provider_from_opts(opts) do
    provider = Keyword.get(opts, :provider)

    if provider in [:llama_cpp, :ollama, :external, :skip] do
      provider
    end
  end

  defp configured?(cfg) do
    cfg
    |> Map.take(["embedding", "llm"])
    |> Map.values()
    |> Enum.any?(&configured_section?/1)
  end

  defp configured_section?(section) when is_map(section) do
    url = Map.get(section, "url") || Map.get(section, :url)
    is_binary(url) and url not in ["", "http://"]
  end

  defp configured_section?(_section), do: false

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp skip_msg do
    Alaja.print_info("LLM setup skipped. Run 'delfos doctor --fix' to complete later.")
    false
  end
end
