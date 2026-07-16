defmodule Delfos.CLI.Spinner do
  @moduledoc """
  Lightweight spinner for short-running operations (< 5s).

  Used by commands that don't justify a full AnimatedBar but where
  the user might otherwise stare at a frozen terminal wondering if
  the command died. Examples:

    * `delfos config show` — loads config.json from disk, decrypts
      api_keys. Usually <50ms but feels weirdly silent in a long
      pipe.
    * `delfos doctor` — probes each LLM endpoint. Fast when servers
      are up, but the embed-server probe can take 1-2s on cold cache.

  ## Design

  Three spinners cycling at 80ms via `:erlang.send_after/3` + a
  child process. Renders to stderr so stdout stays clean for piping
  (`delfos status --json | jq ...`). When stderr is not a TTY
  (CI, redirected) the spinner silently falls back to printing
  the label and proceeding — no animation.

  The "with/2" wrapper handles the lifecycle: starts a spinner
  task, runs the work, stops the spinner. The user just sees
  "Loading config..." then a clear "Done in 47ms" line.

  ## Why not Pulsar?

  Pulsar renders a fixed-height wave around a fixed label. It's
  designed for a multi-second NIF cold-start. For sub-second ops
  a single-line spinner is more appropriate — it doesn't take over
  the terminal, fits alongside other output, and finishes gracefully.

  ## Trade-offs

  Wraps the work in a Task so the spinner can update without blocking
  the work. Cost: 1 extra process. For ops that take < 100ms we
  skip the spinner entirely (no visual benefit).
  """

  @spinner_chars ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  @tick_ms 80

  @doc """
  Runs `fun` while displaying a spinner with `label` on stderr.

  Returns the result of `fun`. The spinner only shows if:
    1. stderr is a TTY (not redirected/piped)
    2. the work takes >= 100ms (otherwise the spinner is more
       distraction than help)

  Usage:

      result = Spinner.with("Loading config...", fn ->
        Manager.load()
      end)
  """
  @spec with(String.t(), (-> any())) :: any()
  def with(label, fun) when is_binary(label) and is_function(fun, 0) do
    if tty?(:stderr) do
      run_with_spinner(label, fun)
    else
      # Non-TTY: skip the spinner, just run the work. We still
      # print a "Done in Nms" line so the user knows the work
      # finished — but only if it took meaningful time.
      t0 = System.monotonic_time(:millisecond)
      result = fun.()
      elapsed = System.monotonic_time(:millisecond) - t0

      if elapsed >= 100 do
        IO.puts(:stderr, "  #{label} — done in #{format_ms(elapsed)}")
      end

      result
    end
  end

  defp run_with_spinner(label, fun) do
    parent = self()

    # Spawn the spinner. It receives :stop to terminate. We use a
    # linked process so it dies if the parent dies (no orphan
    # spinners running in the terminal after Ctrl+C).
    pid =
      spawn_link(fn ->
        send(parent, {:__spinner_started__, self()})
        loop(parent, label, 0, false)
      end)

    receive do
      {:__spinner_started__, ^pid} -> :ok
    after
      200 -> :timeout
    end

    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    elapsed = System.monotonic_time(:millisecond) - t0

    send(pid, :stop)

    # Clear the spinner line and print the result. We only emit the
    # "Done in" line if it took meaningful time — for fast ops the
    # spinner hasn't even started animating yet.
    if elapsed >= 100 do
      IO.write(:stderr, "\r\e[2K  ✓ #{label} — done in #{format_ms(elapsed)}\n")
    else
      IO.write(:stderr, "\r\e[2K")
    end

    result
  end

  defp loop(parent, label, idx, done) do
    if done do
      :ok
    else
      char = Enum.at(@spinner_chars, rem(idx, length(@spinner_chars)))
      IO.write(:stderr, "\r\e[2K  #{char} #{label}")
      receive do
        :stop -> :ok
      after
        @tick_ms ->
          loop(parent, label, idx + 1, false)
      end
    end
  end

  defp tty?(:stderr) do
    try do
      case :io.getopts(:standard_error) do
        {:ok, opts} -> Keyword.get(opts, :tty, false)
        _ -> false
      end
    rescue
      ArgumentError -> false
      _ -> false
    end
  end

  defp format_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp format_ms(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_ms(ms), do: "#{div(ms, 60_000)}m #{format_ms(rem(ms, 60_000))}"
end
