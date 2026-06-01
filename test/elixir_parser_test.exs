defmodule Delfos.Parsers.ElixirParserTest do
  use ExUnit.Case, async: true

  alias Delfos.Parsers.ElixirParser

  @sample """
  defmodule MyApp.Auth do
    @moduledoc "Módulo de autenticación."

    @doc "Valida el token JWT."
    def validate_token(token) do
      # TODO: añadir expiración
      {:ok, token}
    end

    defp internal_helper, do: :ok
  end
  """

  test "extrae módulos correctamente" do
    result = ElixirParser.parse("lib/auth.ex", @sample)
    modules = Enum.filter(result.symbols, &(&1.kind == "module"))
    assert length(modules) == 1
    assert List.first(modules).name == "MyApp.Auth"
  end

  test "extrae funciones públicas y privadas" do
    result = ElixirParser.parse("lib/auth.ex", @sample)
    functions = Enum.filter(result.symbols, &(&1.kind == "function"))
    assert length(functions) == 2
    public = Enum.find(functions, &(&1.name == "validate_token"))
    private = Enum.find(functions, &(&1.name == "internal_helper"))
    assert public.visibility == "public"
    assert private.visibility == "private"
  end

  test "detecta TODOs" do
    result = ElixirParser.parse("lib/auth.ex", @sample)
    assert length(result.todos) == 1
    assert String.contains?(List.first(result.todos).text, "TODO")
  end

  test "cuenta líneas correctamente" do
    result = ElixirParser.parse("lib/auth.ex", @sample)
    assert result.line_count > 0
  end
end
