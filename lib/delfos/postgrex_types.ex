# pgvector + Postgres extensions for Delfos.
#
# Wired into `Delfos.Repo` via:
#
#     config :delfos, Delfos.Repo,
#       types: Delfos.PostgrexTypes,
#       ...
#
# Must be called at the top level of the file (outside any module)
# because `Postgrex.Types.define/3` injects types during compilation.

Postgrex.Types.define(
  Delfos.PostgrexTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)
