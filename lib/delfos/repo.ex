defmodule Delfos.Repo do
  use Ecto.Repo, otp_app: :delfos, adapter: Ecto.Adapters.Postgres

  def init(_type, config) do
    {:ok, Keyword.put(config, :types, Delfos.PostgresTypes)}
  end
end
