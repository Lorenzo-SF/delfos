defmodule DelfosTest do
  @moduledoc """
  Smoke test for the Delfos top-level module.
  """

  use ExUnit.Case, async: true

  test "module is loadable" do
    # El módulo `Delfos` debe existir y ser cargable.
    # No asumimos que tiene una función `hello/0` (el test original era doctest
    # con un módulo vacío — sustituirlo por un smoke test real).
    assert Code.ensure_loaded?(Delfos)
  end
end
