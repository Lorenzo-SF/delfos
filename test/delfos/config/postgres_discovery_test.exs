defmodule Delfos.Config.PostgresDiscoveryTest do
  @moduledoc """
  Tests for PostgresDiscovery.

  Verifies that the discovery module handles the "nothing here" case
  gracefully without crashing the test suite.
  """

  use ExUnit.Case, async: true

  alias Delfos.Config.PostgresDiscovery

  test "discover/0 returns a list (possibly empty) without crashing" do
    # The test environment may or may not have Postgres running. Either
    # way, the function must not raise.
    result = PostgresDiscovery.discover()
    assert is_list(result)
  end

  test "available?/0 returns boolean" do
    assert is_boolean(PostgresDiscovery.available?())
  end

  test "first_reachable/0 returns nil or {host, port} tuple" do
    case PostgresDiscovery.first_reachable() do
      nil ->
        :ok

      {host, port} ->
        assert is_binary(host)
        assert is_integer(port)
        assert port > 0
    end
  end

  test "Server struct fields are populated" do
    server = PostgresDiscovery.Server.new("127.0.0.1", 5432, :running, 0)
    assert server.host == "127.0.0.1"
    assert server.port == 5432
    assert server.kind == :running
    assert server.priority == 0
  end
end
