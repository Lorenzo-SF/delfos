defmodule Dep2 do
  def validate(%{action: _}), do: :ok
  def transform_2(x), do: {:ok, x}
end
