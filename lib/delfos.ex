defmodule Delfos do
  @moduledoc """
  Delfos — semantic knowledge base for software projects.

  Top-level facade. The actual functionality lives in the sub-modules
  (`Delfos.Indexer.*`, `Delfos.Retrieval.*`, `Delfos.MCP.*`, etc.).
  """

  @doc "Returns the application version embedded in the Mix project."
  @doc since: "0.1.0"
  @spec version() :: String.t()
  def version, do: "0.4.5"
end
