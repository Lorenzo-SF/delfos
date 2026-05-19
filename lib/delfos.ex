defmodule Delfos do
  @moduledoc "Punto de entrada principal de Delfos."

  def version, do: Application.spec(:delfos, :vsn) |> to_string()
end
