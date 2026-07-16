defmodule Delfos.CLI.Abort do
  @moduledoc """
  Exception raised by command handlers to signal "stop the program
  with a non-zero exit code".

  `System.halt/1` kills the BEAM in a way that ExUnit cannot trap —
  it terminates the test runner, not just the current call. So
  handlers cannot call it directly if we want them testable.

  The fix: handlers `raise Delfos.CLI.Abort, code: 1`. The top-level
  CLI dispatcher catches this exception and calls `System.halt/1`
  with the requested exit code. Tests can rescue the exception
  and assert the side effects (printed message, persisted config,
  etc.) without killing the test process.

  ## Usage in a handler

      def run(args) when is_list(args) do
        case do_thing(args) do
          :ok -> :ok
          {:error, reason} ->
            raise Delfos.CLI.Abort, message: "X failed: \#{reason}", code: 1
        end
      end

  ## Usage in the dispatcher (top-level main)

      try do
        dispatch_main(args)
      rescue
        e in Delfos.CLI.Abort -> System.halt(e.code)
      end

  ## Usage in tests

      assert_raise Delfos.CLI.Abort, ~r/X failed/, fn ->
        Handler.run(["bad-arg"])
      end

  See `docs/REMAINING_TASKS.md` §21.5 for the original Bug #5/11
  history of `System.halt(1)` in handlers.
  """

  defexception [:message, :code]

  @impl true
  def exception(opts) do
    code = Keyword.get(opts, :code, 1)
    message = Keyword.fetch!(opts, :message)
    %__MODULE__{message: message, code: code}
  end

  @impl true
  def message(%__MODULE__{message: message}), do: message
end
