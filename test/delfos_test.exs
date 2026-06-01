defmodule DelfosTest do
  use ExUnit.Case
  doctest Delfos

  test "greets the world" do
    assert Delfos.hello() == :world
  end
end
