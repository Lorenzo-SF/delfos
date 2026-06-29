defmodule Alaja.CLI.DefinitionTest do
  @moduledoc """
  Smoke test for Alaja.CLI.Definition's pre-flight guarantee.

  The macro must call `Application.ensure_all_started/1` on both
  `:alaja` and the host `otp_app:` declared via `use Alaja.CLI.Definition,
  otp_app: :foo_app`. Without this, escript releases that ship with
  `include_erts: false` will crash on every command with
  "could not lookup Ecto repo" because their supervisor tree never
  started.
  """

  use ExUnit.Case, async: false

  defmodule HostApp do
    @behaviour Application

    @impl true
    def start(_type, _args) do
      :persistent_term.put({__MODULE__, :started}, true)
      {:ok, spawn(fn -> :ok end)}
    end

    @impl true
    def stop(_state), do: :ok
  end

  defmodule FakeCLI do
    use Alaja.CLI.Definition, otp_app: :alaja_cli_def_test_host_app

    command "noop", "Does nothing" do
      run({FakeCLI, :noop_handler})
    end

    def noop_handler(_opts), do: :ok
  end

  setup do
    :persistent_term.erase({Alaja.CLI.DefinitionTest.HostApp, :started})
    :ok
  end

  test "main/1 is callable and returns :ok for the noop command" do
    # No assertion about the host app starting — the FakeApp supervisor
    # isn't actually registered as an OTP app under the given name. This
    # test is purely a smoke check that dispatch_main doesn't crash.
    assert :ok = FakeCLI.main(["noop"])
  end
end
