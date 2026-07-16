defmodule Delfos.CLI.Errors do
  @moduledoc """
  Helpers for printing rich error context to the user.

  Wraps `Alaja.Components.Breadcrumbs` to render the call path that
  led to the error, so users can see *where* in the command pipeline
  the failure happened without reading the source.

  ## Usage

      # In a low-level helper:
      case do_thing() do
        :ok -> :ok
        {:error, reason} ->
          Errors.abort(["delfos", "init", "scan", "file_processor"],
                       "elixir_parser: missing dep tree_sitter",
                       hint: "Run `mix deps.get` and recompile")
      end

      # Or just a breadcrumb without an error:
      Errors.breadcrumb(["delfos", "config", "show", "embedding"])

  The `path` argument is a list of strings, with the most general
  scope first (\"delfos\") and the most specific last
  (\"file_processor\"). The last item is rendered in white, the rest
  in cyan — the same convention used in web UI breadcrumbs.
  """

  alias Alaja
  alias Alaja.Components.Breadcrumbs

  @error_color {220, 50, 50}

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
  Prints an error with a breadcrumb showing the call path. Optional
  `:hint` is a remediation message rendered as a second line in
  dim text. Then halts the process with exit code 1.

  Use this in command entry points and in helpers that have a clear
  remediation path. Don't use it for warnings (use `Alaja.print_warning/1`).
  """
  @spec abort([String.t()], String.t(), keyword()) :: no_return()
  def abort(path, message, opts \\ []) when is_list(path) and is_binary(message) do
    breadcrumb(path)
    error_colored = "#{Alaja.ANSI.fg(elem(@error_color, 0), elem(@error_color, 1), elem(@error_color, 2))}#{message}#{Alaja.ANSI.reset()}"
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

    error_colored = "#{Alaja.ANSI.fg(elem(@error_color, 0), elem(@error_color, 1), elem(@error_color, 2))}#{message}#{Alaja.ANSI.reset()}"

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
