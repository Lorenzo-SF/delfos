defmodule Delfos.Syntax.Utils do
  @moduledoc """
  Shared helpers for working with syntax-highlighting language identifiers.

  Language names are persisted as strings (e.g. `"elixir"`, `"rust"`) but the
  `Alaja.Syntax` API works with atoms. `safe_to_atom/1` is the canonical
  conversion — accepts a binary and returns its `String.to_existing_atom/1`,
  falling back to `:text` for anything the registry does not know about.

  `detect_lang_atom/1` handles the fuller lookup chain used by `delfos query`:
  explicit `:language` field on a search result, then file-extension detection,
  then `:text`.
  """

  @doc """
  Converts a registered language binary to its atom form. Returns `:text`
  for unregistered strings, `nil`, or non-binary input.

  ## Examples

      iex> Delfos.Syntax.Utils.safe_to_atom("elixir")
      :elixir

      iex> Delfos.Syntax.Utils.safe_to_atom("not-a-real-lang")
      :text

      iex> Delfos.Syntax.Utils.safe_to_atom(nil)
      :text
  """
  @spec safe_to_atom(any()) :: atom()
  def safe_to_atom(lang) when is_binary(lang) and lang != "" do
    String.to_existing_atom(lang)
  rescue
    ArgumentError -> :text
  end

  def safe_to_atom(_), do: :text

  @doc """
  Resolves a language atom from a search-result map.

  Lookup order:
    1. `r[:language]` if it's a non-empty binary the registry knows.
    2. `r[:file_path]` if non-empty, via `Alaja.Syntax.detect_language/1`.
    3. `:text` fallback.

  Catches `ArgumentError` defensively in case a future schema lets a
  language string sneak past the registry.
  """
  @spec detect_lang_atom(map()) :: atom()
  def detect_lang_atom(r) when is_map(r) do
    cond do
      is_binary(r[:language]) and r[:language] != "" ->
        safe_to_atom(r[:language])

      is_binary(r[:file_path]) and r[:file_path] != "" ->
        Alaja.Syntax.detect_language(r[:file_path])

      true ->
        :text
    end
  end

  def detect_lang_atom(_), do: :text
end