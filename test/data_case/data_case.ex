defmodule Delfos.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Delfos.Repo
      import Ecto.Changeset
      import Ecto.Query
      import Delfos.DataCase
    end
  end

  setup tags do
    Delfos.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Delfos.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
