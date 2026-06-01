defmodule Delfos.Repo do
  use Ecto.Repo,
    otp_app: :delfos,
    adapter: Ecto.Adapters.Postgres
end
