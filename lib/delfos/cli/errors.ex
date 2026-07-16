defmodule Delfos.CLI.Errors do
  @moduledoc """
  Helpers for printing rich error context to the user.

  Wraps `Alaja.Components.Breadcrumbs` to render the call path that
  led to the error, so users can see *where* in the command pipeline
  the failure happened without reading the source. Wraps
  `Alaja.Components.Message` + `Alaja.Components.Box` for rich
  error/warning messages with a hint box (UX9).

  ## Usage

      # In a low-level helper:
      case do_thing() do
        :ok -> :ok
        {:error, reason} ->
          Errors.abort(["delfos", "init", "scan", "file_processor"],
                       "elixir_parser: missing dep tree_sitter",
                       hint: "Run `mix deps.get` and recompile")
      end

      # Just the message + hint (no halt):
      Errors.warn_with_hint("Embed server unreachable",
                            hint: "Start with: llama-run embed")

      # Or just a breadcrumb without an error:
      Errors.breadcrumb(["delfos", "config", "show", "embedding"])

  The `path` argument is a list of strings, with the most general
  scope first (\"delfos\") and the most specific last
  (\"file_processor\"). The last item is rendered in white, the rest
  in cyan — the same convention used in web UI breadcrumbs.
  """

  alias Alaja
  alias Alaja.Components.{Box, Breadcrumbs, Message}
  alias Alaja.Structures.{ChunkText, MessageInfo}

  @error_color {220, 50, 50}
  @warning_color {220, 180, 0}
  @success_color {0, 200, 80}

  @doc """
  Renders a breadcrumb path. Returns the rendered string (the call
  to `IO.puts` happens here for convenience — for unit testing use
  `Breadcrumbs.render/2` directly).
  """
  @spec breadcrumb([String.t()]) :: :ok
  def breadcrumb(path) when is_list(path) and path != [] do
    bin =
      path
      |> Breadcrumbs.render([])
      |> Alaja.Buffer.to_iodata()
      |> IO.iodata_to_binary()

    IO.puts(bin)
    :ok
  end

  def breadcrumb([]), do: :ok

  @doc """
  Prints a rich error message using `Alaja.Components.Message.render/1`
  with an optional hint Box (UX9). Unlike `Alaja.print_error/1`, this
  version shows the remediation as a separate visual element (rounded
  Box with title "Hint") instead of as a second line of plain text.

  Replaces `Alaja.print_error/1` in places where a hint is available.
  Returns `:ok`.
  """
  @spec print_error(String.t(), keyword()) :: :ok
  def print_error(message, opts \\ []) when is_binary(message) do
    print_message(:error, message, opts)
  end

  @doc """
  Like `print_error/2` but for warnings. Renders in yellow.
  """
  @spec print_warning(String.t(), keyword()) :: :ok
  def print_warning(message, opts \\ []) when is_binary(message) do
    print_message(:warning, message, opts)
  end

  @doc """
  Like `print_error/2` but for success. Renders in green.
  """
  @spec print_success(String.t(), keyword()) :: :ok
  def print_success(message, opts \\ []) when is_binary(message) do
    print_message(:success, message, opts)
  end

  # Internal: render a Message buffer with status colour, then a Box
  # for the hint if present. We use Message.render/1 (not
  # Alaja.print_error/1) because the Buffer pipeline gives us the
  # right cell-aware width when we wrap it in a Box for the hint.
  defp print_message(status, message, opts) do
    color =
      case status do
        :error -> @error_color
        :warning -> @warning_color
        :success -> @success_color
      end

    icon = icon_for(status)

    # Build a single-line Message with two chunks: the icon (coloured)
    # and the message (white). Message.render returns a Buffer.
    msg =
      MessageInfo.new(
        [
          ChunkText.new("#{icon} ", color: {color, :fg}),
          ChunkText.new(message, color: {{255, 255, 255}, :fg})
        ],
        padding: 0,
        add_line: :none
      )

    msg_buf = Message.render(msg)

    # If we have a hint, render it inside a Box right below the
    # message. Otherwise print the message buffer as-is.
    case Keyword.get(opts, :hint) do
      nil ->
        msg_buf |> Alaja.Buffer.to_iodata() |> IO.write()

      hint when is_binary(hint) and hint != "" ->
        Alaja.print_raw("\n")
        msg_buf |> Alaja.Buffer.to_iodata() |> IO.write()
        Alaja.print_raw("\n")

        Box.print(
          "  #{hint}",
          title: "Hint",
          border: :rounded,
          border_color: color,
          padding: 0
        )

      _ ->
        msg_buf |> Alaja.Buffer.to_iodata() |> IO.write()
    end

    Alaja.print_raw("\n")
    :ok
  end

  defp icon_for(:error), do: "✗"
  defp icon_for(:warning), do: "!"
  defp icon_for(:success), do: "✓"

  # Backwards-compatible chunk color tuple accepts either a tuple
  # {r, g, b} or a tuple {rgb, :fg | :bg}. ChunkText uses the second
  # shape; we wrap the bare rgb here so callers don't have to.
  @doc false
  def to_chunk_color(rgb) when is_tuple(rgb) and tuple_size(rgb) == 3, do: {rgb, :fg}

  @doc """
  Prints an error with a breadcrumb showing the call path. Optional
  `:hint` is a remediation message rendered as a second line in
  dim text. Then halts the process with exit code 1.

  Use this in command entry points and in helpers that have a clear
  remediation path. Don't use it for warnings (use `Alaja.print_warning/1`).
  """
  @spec abort([String.t()], String.t(), keyword()) :: no_return()
  def abort(path, message, opts \\ []) when is_list(path) and is_binary(message) do
    breadcrumb(path)

    error_colored =
      "#{Alaja.ANSI.fg(elem(@error_color, 0), elem(@error_color, 1), elem(@error_color, 2))}#{message}#{Alaja.ANSI.reset()}"

    IO.puts(error_colored)

    case Keyword.get(opts, :hint) do
      nil ->
        :ok

      hint when is_binary(hint) and hint != "" ->
        IO.puts("#{Alaja.ANSI.dim()}Hint: #{hint}#{Alaja.ANSI.reset()}")

      _ ->
        :ok
    end

    System.halt(1)
  end

  @doc """
  Non-halting variant of `abort/3`. Prints the breadcrumb + message
  but lets the caller decide whether to continue or halt. Returns `:ok`.
  """
  @spec render_error([String.t()], String.t(), keyword()) :: :ok
  def render_error(path, message, opts \\ []) when is_list(path) and is_binary(message) do
    breadcrumb(path)

    error_colored =
      "#{Alaja.ANSI.fg(elem(@error_color, 0), elem(@error_color, 1), elem(@error_color, 2))}#{message}#{Alaja.ANSI.reset()}"

    IO.puts(error_colored)

    case Keyword.get(opts, :hint) do
      hint when is_binary(hint) and hint != "" ->
        IO.puts("#{Alaja.ANSI.dim()}Hint: #{hint}#{Alaja.ANSI.reset()}")

      _ ->
        :ok
    end

    :ok
  end
end
