defmodule Delfos.CLI.LLMGuardCandilTest do
  @moduledoc """
  Tests that `LLMGuard.check/1` now routes through `Candil.Health.probe/2`
  instead of opening a raw TCP socket.
  """

  use ExUnit.Case, async: false

  alias Delfos.CLI.LLMGuard

  defmodule FakeHealth do
    @moduledoc false
    def probe(_url, _opts), do: %{reachable: true, latency_ms: 1}
  end

  defmodule UnreachableHealth do
    @moduledoc false
    def probe(_url, _opts), do: %{reachable: false, error: "connection refused"}
  end

  defmodule CountingHealth do
    @moduledoc false
    def probe(url, opts), do: send(self(), {:probe, url, opts})
  end

  setup do
    fake_home = Path.join(System.tmp_dir!(), "delfos_llm_guard_candil_#{System.unique_integer()}")
    File.mkdir_p!(fake_home)

    original_home = System.get_env("HOME")
    original_xdg = System.get_env("XDG_CONFIG_HOME")
    System.put_env("HOME", fake_home)
    System.put_env("XDG_CONFIG_HOME", fake_home)

    on_exit(fn ->
      System.put_env("HOME", original_home)
      if original_xdg, do: System.put_env("XDG_CONFIG_HOME", original_xdg)
      File.rm_rf!(fake_home)
    end)

    :ok
  end

  test "check/1 calls Candil.Health.probe/2 for required endpoints" do
    Application.put_env(:delfos, :candil_health, FakeHealth)
    on_exit(fn -> Application.delete_env(:delfos, :candil_health) end)

    assert LLMGuard.check("scan") == :ok
  end

  test "check/1 returns :halt when Candil.Health reports unreachable" do
    Application.put_env(:delfos, :candil_health, UnreachableHealth)
    on_exit(fn -> Application.delete_env(:delfos, :candil_health) end)

    assert LLMGuard.check("scan") == {:halt, :required}
  end

  test "check/1 returns :warn for optional commands when unreachable" do
    Application.put_env(:delfos, :candil_health, UnreachableHealth)
    on_exit(fn -> Application.delete_env(:delfos, :candil_health) end)

    assert LLMGuard.check("watch") == :warn
  end

  test "check/1 uses Candil.Health and not TCP probe" do
    Application.put_env(:delfos, :candil_health, CountingHealth)
    on_exit(fn -> Application.delete_env(:delfos, :candil_health) end)

    LLMGuard.check("query")

    assert_received {:probe, _url, _opts}
  end
end
