defmodule Delfos do
  @moduledoc """
  Delfos — semantic knowledge base for software projects.

  Top-level facade. The actual functionality lives in the sub-modules
  (`Delfos.Indexer.*`, `Delfos.Retrieval.*`, `Delfos.MCP.*`, etc.).
  """

  @doc """
  Returns the application version embedded in the loaded Mix project.

  Reads it from the application spec at runtime so that a release-based
  binary (or any deployment that doesn't ship `Mix.Project`) reports
  the right number to `delfos version`, `delfos doctor`, and CI smoke
  checks. Falls back to a placeholder only if the spec is missing.
  """
  @doc since: "0.1.0"
  @spec version() :: String.t()
  def version do
    case Application.spec(:delfos, :vsn) do
      nil -> "0.0.0+unknown"
      version -> to_string(version)
    end
  end
end
