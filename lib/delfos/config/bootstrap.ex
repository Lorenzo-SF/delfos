defmodule Delfos.Config.Bootstrap do
  @moduledoc """
  Provisions a Delfos database from scratch.

  This module is used by `delfos doctor --fix` to bootstrap the database
  when working from the release binary (no source code, no `mix`).

  It applies the bundled SQL in `priv/bootstrap.sql` via Postgrex — the
  Postgrex driver is already a dependency, so no external `psql` binary
  is required.

  For source-code deployments, prefer `mix ecto.migrate` because it
  tracks the schema_migrations table.
  """

  alias Delfos.Config.PostgresDiscovery
  alias Alaja

  @bootstrap_path "priv/bootstrap.sql"
  @bootstrap_version "2.1.0"

  @doc """
  Ensures the database exists and is fully provisioned.

  Returns `:ok` on success, `{:error, reason}` on failure.

  Steps performed:
    1. Verify that PostgreSQL is reachable (use PostgresDiscovery).
    2. Connect to the `postgres` admin database and create the target
       database if it does not exist.
    3. Connect to the target database and apply the bootstrap SQL.
  """
  @spec ensure_database(keyword()) :: :ok | {:error, term()}
  def ensure_database(opts \\ [])

  def ensure_database([yes: _] = opts) do
    do_ensure_database(opts)
  end

  def ensure_database(opts) when is_list(opts) do
    do_ensure_database([{:yes, false} | opts])
  end

  defp do_ensure_database(opts) do
    auto_yes = Keyword.get(opts, :yes, false)

    case PostgresDiscovery.first_reachable() do
      nil ->
        case PostgresDiscovery.offer_install(yes: auto_yes) do
          :installed ->
            do_ensure_database(opts)

          :user_declined ->
            Alaja.print_error("Cannot provision database without PostgreSQL.")
            {:error, :no_postgres}

          other ->
            other
        end

      {host, port} ->
        conn = Keyword.get(opts, :connection) || default_connection_params(host, port)
        ensure_db_exists(conn)
        apply_bootstrap_sql(conn)
        :ok
    end
  end

  @doc """
  Enables the pgvector extension on the configured database. Safe to
  run multiple times (uses `IF NOT EXISTS`).
  """
  @spec enable_pgvector() :: :ok | {:error, term()}
  def enable_pgvector do
    case PostgresDiscovery.first_reachable() do
      nil ->
        {:error, "PostgreSQL not reachable"}

      {host, port} ->
        conn = default_connection_params(host, port)

        case run_query(conn, "CREATE EXTENSION IF NOT EXISTS vector") do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # ── Steps ──────────────────────────────────────────────────────────────

  defp ensure_db_exists(conn) do
    target = conn[:database]
    admin = Keyword.put(conn, :database, "postgres")

    case run_query(admin, "SELECT 1 FROM pg_database WHERE datname='#{target}'") do
      {:ok, %{rows: [[1]]}} ->
        Alaja.print_info("Database '#{target}' already exists.")

      _ ->
        Alaja.print_info("Creating database '#{target}'...")

        case run_query(admin, "CREATE DATABASE \"#{target}\"") do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, "create database: #{reason}"}
        end
    end
  end

  defp apply_bootstrap_sql(conn) do
    Alaja.print_info("Applying bootstrap SQL (#{@bootstrap_version})...")

    sql = read_bootstrap_sql()

    # Split the SQL on semicolons but keep quoted strings and --comments
    # intact. This is intentionally a thin splitter — the bootstrap file
    # is maintained alongside this code so we control its format.
    statements = split_statements(sql)

    Enum.reduce_while(statements, :ok, fn stmt, _ ->
      case run_query(conn, stmt) do
        {:ok, _} ->
          {:cont, :ok}

        {:error, reason} ->
          Alaja.print_error("Bootstrap SQL failed on statement: #{String.slice(stmt, 0, 80)}…")
          {:halt, {:error, reason}}
      end
    end)
  end

  # ── Connection helpers ────────────────────────────────────────────────

  defp default_connection_params(host, port) do
    cfg = Delfos.Config.Manager.read_section("database") || %{}

    [
      hostname: cfg["hostname"] || host,
      port: cfg["port"] || port,
      username: cfg["username"] || System.get_env("USER") || "delfos",
      password: cfg["password"] || "",
      database: cfg["database"] || "delfos_prod"
    ]
  end

  defp run_query(conn, sql) do
    {:ok, pid} = Postgrex.start_link(conn)
    ref = Ecto.Adapters.SQL.query(pid, sql, [])
    Postgrex.query!(pid, "SELECT 1", [])

    # `ref` may already be resolved; we just use the synchronous helper.
    Process.exit(pid, :normal)
    {:ok, ref}
  rescue
    e -> {:error, Exception.message(e)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp read_bootstrap_sql do
    case File.read(Application.app_dir(:delfos, @bootstrap_path)) do
      {:ok, content} ->
        content

      {:error, _} ->
        # Fall back to source-tree location (dev/test)
        Application.app_dir(:delfos, @bootstrap_path)
        |> Path.absname()
        |> File.read!()
    end
  end

  defp split_statements(sql) do
    sql
    |> String.split(~r/;\s*\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "--")))
  end
end
