defmodule Delfos.Application do
  @moduledoc """
  Supervision tree for Delfos.

  Startup modes:
    - `:cli` (default) — interactive CLI. The Watcher starts only if
      `watch: true` is configured.
    - `:mcp` — MCP stdio server. The Watcher ALWAYS starts, but logs
      go to stderr (stdout is the MCP channel).

  The mode is set before `start_link` via:
      Application.put_env(:delfos, :mode, :mcp)
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    mode = Application.get_env(:delfos, :mode, :cli)
    configure_logger_for_mode(mode)
    Delfos.Syntax.Registry.register_all()

    # Arranca Finch ANTES del árbol de supervisión.
    # El transporte HTTP lo gestiona Apero.Http, que mantiene su propio
    # pool bajo Apero.Http.Finch. Llamamos ensure_started/0 aquí para
    # que el pool esté listo antes de cualquier request HTTP del CLI.
    Apero.Http.Finch.ensure_started()

    children =
      [
        Delfos.RepoStarter,
        # max_children previene OOM por bug/DoS (S19). Default es :infinity.
        {Task.Supervisor, name: Delfos.TaskSupervisor, max_children: 50},
        {Delfos.MCP.IndexBroadcaster, []}
      ] ++ watcher_children(mode) ++ health_children(mode)

    sup =
      Supervisor.start_link(children, strategy: :one_for_one, name: Delfos.Supervisor)

    # The Repo is NOT auto-started here — many CLI commands (e.g.
    # `delfos version`, `delfos config show`) don't need it. The
    # app's main/1 in `Delfos.CLI` is responsible for calling
    # `Delfos.RepoStarter.start_repo/0` synchronously before
    # dispatching commands that touch the database.

    # Auto-apply migrations on boot. Critical for releases — the user
    # installs `delfos` once and runs any command; the first time the
    # app starts we check schema_migrations and apply anything pending.
    # Migrations live in `priv/repo/migrations/`, automatically bundled
    # by `mix release` into `<release>/lib/delfos-<vsn>/priv/...` so
    # `Application.app_dir/2` resolves them at runtime. The check is
    # best-effort: if the DB is unreachable, we silently let the user
    # see the actual error from the command they ran (instead of
    # swallowing it here).
    maybe_run_migrations()

    sup
  end

  @impl true
  def stop(_state), do: :ok

  # ---------------------------------------------------------------------------
  # Logger — en modo MCP redirigir a stderr para no contaminar stdout
  # ---------------------------------------------------------------------------

  @doc """
  Configura el logger según el modo de operación.
  Es público para que el MCP server pueda re-configurarlo si arranca
  después de que la app ya esté iniciada en modo CLI.
  """
  def configure_logger_for_mode(:mcp) do
    Logger.configure_backend(:console, device: :standard_error)
    Logger.configure(level: :warning)
  end

  def configure_logger_for_mode(_), do: :ok

  # ---------------------------------------------------------------------------
  # Watcher
  # ---------------------------------------------------------------------------

  defp watcher_children(:mcp) do
    [{Delfos.Indexer.Watcher, [mode: :mcp]}]
  end

  defp watcher_children(_cli) do
    if Application.get_env(:delfos, :watch, false) do
      [{Delfos.Indexer.Watcher, [mode: :cli]}]
    else
      []
    end
  end

  # ---------------------------------------------------------------------------
  # Health check (Botica)
  # ---------------------------------------------------------------------------

  defp health_children(_mode) do
    if Application.get_env(:delfos, :health_check, false) do
      [{Delfos.Health, []}]
    else
      []
    end
  end

  # ── Auto-migrate ─────────────────────────────────────────────────────

  # Best-effort migration runner. Triggered once on boot.
  #
  # Behavior:
  #   * If the database is unreachable, do nothing (let the calling
  #     command surface the real error — `delfos setup db` handles it).
  #   * If `schema_migrations` does not exist (fresh DB), run all
  #     migrations from `priv/repo/migrations/`.
  #   * If `schema_migrations` exists, only apply pending ones.
  #   * All output goes to stderr so MCP-mode stdio stays clean.
  @doc false
  def maybe_run_migrations do
    Application.get_env(:delfos, :auto_migrate, true)
    |> if(do: :ok, else: :skip)
    |> case do
      :skip -> :ok
      :ok -> do_auto_migrate()
    end
  rescue
    # Auto-migrate must NEVER crash the supervisor. The user would
    # see a confusing stack trace before any command even runs.
    e ->
      Logger.warning("[delfos] auto-migrate skipped: #{Exception.message(e)}")
      :ok
  end

  defp do_auto_migrate do
    migrations_dir = Application.app_dir(:delfos, "priv/repo/migrations")

    cond do
      not File.exists?(migrations_dir) ->
        :ok

      true ->
        migrate_via_ecto(migrations_dir)
    end
  end

  defp migrate_via_ecto(migrations_dir) do
    # Ensure the repo is up before we ask Ecto to migrate. We do this
    # in a Task so a slow DB does not block the supervisor's start.
    # Usamos `start` (no `start_link`) para no enlazar el ciclo de vida
    # del task al supervisor (A1).
    Task.start(fn ->
      try do
        # El repo es el módulo, SIEMPRE. `Application.get_env(:delfos,
        # Delfos.Repo)` devuelve la keyword list de config del repo
        # (definida con `config :delfos, Delfos.Repo, ...`), NO el
        # módulo — usarla como repo rompe `query!` con un badmatch.
        repo = Delfos.Repo

        # Probe connectivity first.
        case Ecto.Adapters.SQL.query!(repo, "SELECT 1") do
          {:ok, _} ->
            apply_pending_migrations(repo, migrations_dir)

          {:error, probe_reason} ->
            # SE-4 (S20): log the probe failure. Before, the catch-all
            # below silently swallowed this — users with bad DB config
            # would see a confusing "command failed" later with no clue
            # that auto-migrate had already failed at boot.
            Logger.error(
              "[delfos] auto-migrate probe failed: #{inspect(probe_reason)}. " <>
                "Run 'delfos doctor' to debug the DB connection."
            )

            :ok
        end
      catch
        :exit, reason ->
          Logger.error(
            "[delfos] auto-migrate task exited: #{inspect(reason)}. " <>
              "Migrations were NOT applied — verify with 'delfos doctor'."
          )

          :ok

        kind, reason ->
          Logger.error(
            "[delfos] auto-migrate #{kind}: #{inspect(reason)}. " <>
              "Migrations were NOT applied — verify with 'delfos doctor'."
          )

          :ok
      end
    end)
  end

  defp apply_pending_migrations(repo, migrations_dir) do
    files =
      migrations_dir
      |> File.ls!()
      |> Enum.sort()

    paths = Enum.map(files, fn name -> Path.join(migrations_dir, name) end)

    # `Ecto.Migrator.with_repo/3` is the canonical wrapper for running
    # migrations — it temporarily starts the repo if needed and
    # returns `{:ok, value, apps}` or `{:error, reason}`. This is
    # what `mix ecto.migrate` itself uses under the hood.
    case Ecto.Migrator.with_repo(
           repo,
           fn repo ->
             Ecto.Migrator.run(repo, paths, :up, all: true, log_migrations_sql: false)
           end,
           mode: :temporary
         ) do
      {:ok, applied, _apps} ->
        Enum.each(applied, fn {status, migration, _} ->
          Logger.info("[delfos] auto-migrate #{status}: #{migration.version} #{migration.name}")
        end)

      {:error, reason} ->
        Logger.debug("[delfos] auto-migrate error: #{inspect(reason)}")

      other ->
        Logger.debug("[delfos] Ecto.Migrator returned: #{inspect(other)}")
    end
  end
end
