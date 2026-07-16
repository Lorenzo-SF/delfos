defmodule Delfos.LLM.Response do
  @moduledoc """
  Normalises responses from heterogeneous LLM gateways into a single
  printable text shape.

  Most OpenAI-compatible servers return only the assistant text:

      "Some explanation of the symbol..."

  But a few (notably the local `llama-server` bridge fronting `gpt-oss`
  and other non-strictly-compliant gateways) hand back the full
  response envelope:

      %{
        content: "Some explanation of the symbol...",
        role: "assistant",
        finish_reason: "length"
      }

  Mixed shapes crashed callers with `String.Chars not implemented for
  Map` whenever the data crossed the IO/DB boundary. This module
  centralises the normalisation so every consumer (CLI commands,
  persistence, MCP tools) can rely on getting back either a non-empty
  trimmed string or `nil`.

  ## Usage

      case Client.chat(messages, use_case: :explain) do
        {:ok, raw} ->
          case Delfos.LLM.Response.normalize(raw) do
            nil -> Alaja.print_warning("LLM returned empty")
            text -> Alaja.print_raw(text)
          end

        {:error, reason} ->
          Alaja.print_error("Error: \#{inspect(reason)}")
      end

  ## Function clauses handled

  | Input                              | Output                          |
  |------------------------------------|---------------------------------|
  | `nil`                              | `nil`                           |
  | `""` / whitespace-only binary      | `nil`                           |
  | non-empty binary                   | `String.trim/1` of input        |
  | `%{content: binary}`               | `String.trim/1` of `content`    |
  | `%{"content" => binary}`           | `String.trim/1` of `content`    |
  | anything else                      | `nil` + `Logger.debug`          |

  The `nil` sentinel lets callers easily skip and warn on empty results
  (common when `max_tokens` is too small and `finish_reason="length"`),
  rather than persisting an unusable string.
  """

  require Logger

  @doc """
  Extracts the printable text from a raw LLM response.

  Returns `nil` when the response is empty (nil, empty string, or
  whitespace-only) or in an unrecognised shape. The unexpected shape
  case is logged at `debug` level — it indicates a new gateway quirk
  to be added to the function head table.
  """
  @spec normalize(any()) :: String.t() | nil

  def normalize(nil), do: nil

  def normalize(""), do: nil

  def normalize(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # Atom-keyed envelope shape: %{content: "..."} (Elixir-native hash)
  def normalize(%{content: content}) when is_binary(content), do: normalize(content)

  # String-keyed envelope shape: %{"content" => "..."} (decoded JSON)
  def normalize(%{"content" => content}) when is_binary(content), do: normalize(content)

  def normalize(other) do
    Logger.debug(
      "Delfos.LLM.Response.normalize/1: unexpected response shape #{inspect(other)}, " <>
        "returning nil. If this shape comes from a new gateway, add a clause here."
    )

    nil
  end
end
