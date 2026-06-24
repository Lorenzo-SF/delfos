ExUnit.start()

# M-2 audit fix: el test_helper original forzaba `Ecto.Adapters.SQL.Sandbox.mode(Delfos.Repo, :manual)`
# lo que hacía que NINGÚN test corriera sin una DB Postgres disponible. Esto es fatal
# para CI y para `mix test --warnings-as-errors` (tests sin DB fallaban al cargar).
#
# Estrategia nueva:
#   1. Los tests que NO tocan Postgres (chunker, elixir_parser, reranker, integration)
#      corren siempre, sin necesidad de DB.
#   2. Los tests que SÍ tocan Postgres (factory, data_case) se marcan con @tag :integration
#      y solo corren si MIX_ENV=integration o si se pasa --include integration.
#
# Si Delfos.Repo está disponible Y la DB responde, activamos sandbox automáticamente.
defmodule Delfos.TestHelper do
  @moduledoc false

  def maybe_setup_sandbox do
    case Code.ensure_loaded(Ecto.Adapters.SQL.Sandbox) do
      {:module, _} ->
        try do
          Ecto.Adapters.SQL.Sandbox.checkout(Delfos.Repo, opts: [timeout: 1_500])
          Ecto.Adapters.SQL.Sandbox.mode(Delfos.Repo, {:shared, self()})

          on_exit(fn ->
            try do
              Ecto.Adapters.SQL.Sandbox.checkin(Delfos.Repo, [])
            catch
              :exit, _ -> :ok
              _, _ -> :ok
            end
          end)

          :ok
        catch
          :exit, _ -> :no_db
          _, _ -> :no_db
        end

      _ ->
        :no_module
    end
  end
end

_ = Delfos.TestHelper.maybe_setup_sandbox()

# Configuración por defecto: excluir :integration a menos que se pida explícitamente.
ExUnit.configure(
  exclude: [
    integration: System.get_env("MIX_ENV") != "integration",
    postgres: System.get_env("MIX_ENV") != "integration"
  ]
)
