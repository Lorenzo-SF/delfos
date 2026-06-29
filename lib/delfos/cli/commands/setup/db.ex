defmodule Delfos.CLI.Commands.Setup.DB do
  @moduledoc """
  Interactive database setup for Delfos.

  Detects available PostgreSQL options (local binary, Docker) and guides
  the user through choosing, installing, and configuring a database.
  """

  alias Alaja
  alias Alaja.Components.Header
  alias Alaja.Printer.Interactive

  @doc """
  Runs the interactive DB setup. Returns `true` if setup completed, `false` otherwise.
  """
  def run do
    case check_reachable() do
      {:ok, msg} ->
        Alaja.print_success("Database: #{msg}")
        verify_migrated()

      _ ->
        Header.print("Database setup",
          subtitle: "PostgreSQL is required for Delfos",
          size: :small
        )

        Alaja.print_raw("\n")
        choose_and_setup()
    end
  end

  defp check_reachable do
    case Delfos.Repo.query("SELECT version()") do
      {:ok, %{rows: [[ver]]}} ->
        {:ok, String.slice(ver, 0, 60)}

      _ ->
        check_pg_isready()
    end
  rescue
    _ -> check_pg_isready()
  end

  defp check_pg_isready do
    case System.cmd("pg_isready", ["-q"], stderr_to_stdout: true) do
      {_, 0} -> {:ok, "pg_isready: accepting connections"}
      _ -> {:error, :not_reachable}
    end
  rescue
    _ -> {:error, :not_reachable}
  end

  defp verify_migrated do
    case Delfos.Repo.query("SELECT COUNT(*) FROM schema_migrations") do
      {:ok, _} ->
        Alaja.print_success("Migrations: up to date")
        true

      {:error, _} ->
        case Interactive.yesno("Database needs migrations. Run them now?", default: :yes) do
          :yes ->
            run_migrations()

          :no ->
            Alaja.print_info("Run migrations later: 'delfos doctor --fix'")
            true
        end
    end
  rescue
    _ ->
      case Interactive.yesno("Database needs migrations. Run them now?", default: :yes) do
        :yes ->
          run_migrations()

        :no ->
          Alaja.print_info("Run migrations later: 'delfos doctor --fix'")
          true
      end
  end

  defp choose_and_setup do
    has_local = has_command?("psql") or has_command?("pg_isready")
    has_docker = has_command?("docker")
    has_brew = has_command?("brew")
    has_apt = has_command?("apt-get")

    options = build_options(has_local, has_docker, has_brew, has_apt)

    Alaja.print_info("Available options:")
    Enum.each(options, fn {txt, _} ->
      Alaja.print_raw("  #{txt}\n")
    end)

    case Interactive.question_with_options(
           "How would you like to set up PostgreSQL? (paste the full option text)",
           options,
           color: :cyan
         ) do
      :local ->
        setup_local()

      :docker ->
        setup_docker()

      :brew ->
        install_via_brew()

      :apt ->
        install_via_apt()

      :remote ->
        setup_remote()

      :manual ->
        skip_msg()

      :skip ->
        skip_msg()

      :error ->
        Alaja.print_error("Option not recognised. Available options:")
        Enum.each(options, fn {txt, _} ->
          Alaja.print_raw("  #{txt}\n")
        end)
        choose_and_setup()
    end
  end

  defp build_options(has_local, has_docker, has_brew, has_apt) do
    opts = []

    opts =
      if has_local do
        ver = detect_local_version()
        [{~s[Use existing local PostgreSQL (#{ver})], :local} | opts]
      else
        opts
      end

    opts =
      if has_docker do
        [{"Start PostgreSQL via Docker (recommended — no config needed)", :docker} | opts]
      else
        opts
      end

    base =
      if has_brew do
        opts ++ [{"Install PostgreSQL via Homebrew", :brew}]
      else
        if has_apt do
          opts ++ [{"Install PostgreSQL via apt-get", :apt}]
        else
          opts ++ [{"Install manually (I'll do it myself)", :manual}]
        end
      end

    # Remote DB is always offered (you might have a Postgres on another machine)
    (base ++ [{"Connect to remote PostgreSQL (host:port)", :remote}])
    |> Kernel.++([{"Skip — I'll set it up later", :skip}])
  end

  defp has_command?(cmd) do
    case System.cmd("which", [cmd], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp detect_local_version do
    case System.cmd("psql", ["--version"], stderr_to_stdout: true) do
      {out, 0} -> out |> String.trim() |> String.split(",") |> List.first() || "unknown"
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp setup_local do
    case Interactive.yesno("Create database and run migrations now?", default: :yes) do
      :yes ->
        create_db_and_migrate()
        Alaja.print_success("Database ready")
        true

      :no ->
        Alaja.print_info("Run 'delfos doctor --fix' to complete DB setup later.")
        false
    end
  end

  defp setup_docker do
    container = "delfos-postgres"

    case Interactive.yesno(
           "Start PostgreSQL in Docker container '#{container}' (port 5432)?",
           default: :yes
         ) do
      :yes ->
        case start_docker_pg(container) do
          :ok ->
            Alaja.print_info("Waiting for PostgreSQL to be ready...")

            case poll_pg("localhost", 5432, 30_000) do
              :ok ->
                Alaja.print_success("PostgreSQL is running in Docker")
                Alaja.print_raw("\n")
                create_db_and_migrate()

              {:error, reason} ->
                Alaja.print_error("Timed out: #{reason}")
                false
            end

          {:error, reason} ->
            Alaja.print_error("Failed: #{reason}")
            false
        end

      :no ->
        Alaja.print_info("Run 'delfos doctor --fix' to complete DB setup later.")
        false
    end
  end

  defp start_docker_pg(container) do
    case System.cmd("docker", ["ps", "-q", "--filter", "name=^#{container}$"],
           stderr_to_stdout: true
         ) do
      {pid, 0} when pid != "" and pid != "\n" ->
        Alaja.print_info("Container already running (#{String.trim(pid)})")
        :ok

      _ ->
        Alaja.print_info("Pulling postgres:16 image and starting container...")

        case System.cmd("docker", [
               "run",
               "-d",
               "--name",
               container,
               "-e",
               "POSTGRES_USER=postgres",
               "-e",
               "POSTGRES_PASSWORD=postgres",
               "-e",
               "POSTGRES_DB=delfos_dev",
               "-p",
               "5432:5432",
               "postgres:16"
             ]) do
          {_, 0} -> :ok
          {err, _} -> {:error, String.trim(err)}
        end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp poll_pg(host, port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_poll(host, port, deadline)
  end

  defp do_poll(host, port, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, "timeout after #{30_000}ms"}
    else
      case System.cmd(
             "pg_isready",
             ["-h", host, "-p", to_string(port), "-q"],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          :ok

        _ ->
          :timer.sleep(1500)
          do_poll(host, port, deadline)
      end
    end
  rescue
    _ ->
      :timer.sleep(1500)
      do_poll(host, port, deadline)
  end

  defp install_via_brew do
    case Interactive.yesno("Install PostgreSQL via 'brew install postgresql'?", default: :yes) do
      :yes ->
        Alaja.print_info("Installing PostgreSQL...")

        case System.cmd("brew", ["install", "postgresql"], stderr_to_stdout: true) do
          {_, 0} ->
            Alaja.print_success("PostgreSQL installed")
            Alaja.print_info("Starting service...")

            System.cmd("brew", ["services", "start", "postgresql"], stderr_to_stdout: true)

            case poll_pg("localhost", 5432, 15_000) do
              :ok ->
                Alaja.print_raw("\n")
                create_db_and_migrate()

              {:error, _} ->
                Alaja.print_info("PostgreSQL installed. Start it and run 'delfos doctor --fix'.")
                true
            end

          {err, _} ->
            Alaja.print_error("Install failed: #{String.trim(err)}")
            false
        end

      :no ->
        skip_msg()
    end
  end

  defp install_via_apt do
    case Interactive.yesno("Install PostgreSQL via 'apt-get install postgresql'?", default: :yes) do
      :yes ->
        steps = [
          {"sudo apt-get update -qq", "Updating package lists..."},
          {"sudo apt-get install -y -qq postgresql postgresql-contrib",
           "Installing PostgreSQL..."},
          {"sudo systemctl start postgresql", "Starting PostgreSQL service..."}
        ]

        result =
          Enum.reduce_while(:ok, steps, fn {cmd, label}, _acc ->
            Alaja.print_info(label)

            case System.cmd("bash", ["-c", cmd], stderr_to_stdout: true) do
              {_, 0} -> {:cont, :ok}
              {err, _} -> {:halt, {:error, String.trim(err)}}
            end
          end)

        case result do
          :ok ->
            case poll_pg("localhost", 5432, 15_000) do
              :ok ->
                Alaja.print_success("PostgreSQL installed and running")
                Alaja.print_raw("\n")
                create_db_and_migrate()

              {:error, _} ->
                Alaja.print_info(
                  "PostgreSQL installed. Start it: 'sudo systemctl start postgresql'"
                )

                Alaja.print_info("Then run 'delfos doctor --fix'")
                true
            end

          {:error, reason} ->
            Alaja.print_error("Install failed: #{reason}")
            false
        end

      :no ->
        skip_msg()
    end
  end

  defp create_db_and_migrate do
    db_name =
      Application.get_env(:delfos, Delfos.Repo, []) |> Keyword.get(:database, "delfos_dev")

    Alaja.print_info("Creating database '#{db_name}'...")

    case System.cmd("createdb", [db_name], stderr_to_stdout: true) do
      {_, 0} -> Alaja.print_success("Database created")
      {_, _} -> Alaja.print_info("Database may already exist — continuing")
    end

    install_pgvector()
    run_migrations()
  end

  defp install_pgvector do
    db_name =
      Application.get_env(:delfos, Delfos.Repo, []) |> Keyword.get(:database, "delfos_dev")

    Alaja.print_info("Installing pgvector extension...")

    case System.cmd("psql", ["-d", db_name, "-c", "CREATE EXTENSION IF NOT EXISTS vector"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Alaja.print_success("pgvector extension installed")

      {_, _} ->
        Alaja.print_info("Could not auto-install pgvector. Run manually:")
        Alaja.print_raw("  psql -d #{db_name} -c 'CREATE EXTENSION vector;'\n")
    end
  end

  defp run_migrations do
    Alaja.print_info("Running database migrations...")

    case Delfos.Repo.query("SELECT COUNT(*) FROM schema_migrations") do
      {:ok, %{rows: [[count]]}} ->
        Alaja.print_success("Migrations: #{count} already applied")
        :ok

      {:error, _} ->
        Alaja.print_info("Migrations table not found — need to initialize")
        apply_migrations()
    end
  rescue
    _ ->
      Alaja.print_info("Checking migration status...")
      apply_migrations()
  end

  defp apply_migrations do
    migration_dir = Application.app_dir(:delfos, "priv/repo/migrations")

    cond do
      File.exists?(migration_dir) ->
        files = migration_dir |> File.ls!() |> Enum.sort()

        Alaja.print_info("Applying #{length(files)} migration(s)...")

        migrated =
          Enum.map(files, fn file ->
            path = Path.join(migration_dir, file)
            code = File.read!(path)

            case Code.eval_string(code) do
              {_mod, _binding} ->
                Alaja.print_success("  #{file}")
                :ok

              _ ->
                Alaja.print_warning("  #{file} — could not apply automatically")
                :error
            end
          end)

        if Enum.all?(migrated, &(&1 == :ok)) do
          Alaja.print_success("Database ready")
          :ok
        else
          Alaja.print_warning("Some migrations need manual attention")
          Alaja.print_info("Run: cd delfos && mix ecto.migrate")
          :ok
        end

      true ->
        Alaja.print_warning("No migration files found in #{migration_dir}")
        Alaja.print_info("Run: cd delfos && mix ecto.migrate")
        :ok
    end
  rescue
    e ->
      Alaja.print_warning("Could not auto-migrate: #{Exception.message(e)}")
      Alaja.print_info("Run manually: cd delfos && mix ecto.migrate")
      :ok
  end

  defp skip_msg do
    Alaja.print_info("DB setup skipped. Run 'delfos doctor --fix' to complete later.")
    false
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Remote PostgreSQL
  # ═══════════════════════════════════════════════════════════════════════

  @doc """
  Connect to a remote PostgreSQL instance. The user provides
  host:port and credentials. pgvector must already be installed on
  the remote server (we cannot install it remotely).
  """
  def setup_remote do
    Alaja.print_raw("\n")
    Header.print("Remote PostgreSQL setup",
      subtitle: "Point Delfos at an existing PostgreSQL on another machine",
      size: :small
    )

    Alaja.print_raw("\n")
    host = ask_string("PostgreSQL host or IP", default: "")
    port = ask_int("PostgreSQL port", default: 5432)
    user = ask_string("PostgreSQL user", default: "postgres")
    password = ask_secret("PostgreSQL password (input hidden)", default: "")
    db_name = ask_string("Database name (will be created if missing)", default: "delfos_dev")

    if host == "" do
      Alaja.print_error("Host is required")
      skip_msg()
    else
      # Persist config first so create_db_and_migrate can read it
      cfg = %{
        "host" => host,
        "port" => port,
        "user" => user,
        "password" => password,
        "database" => db_name
      }

      update_db_config(cfg)

      Alaja.print_info("Probing connection to #{host}:#{port}...")

      case poll_pg(host, port, 15_000) do
        :ok ->
          Alaja.print_success("Connection OK")

          Alaja.print_info("Creating database '#{db_name}' if missing...")

          case System.cmd("createdb", ["-h", host, "-p", to_string(port), "-U", user, db_name],
                 stderr_to_stdout: true,
                 env: [{"PGPASSWORD", password}]
               ) do
            {_, 0} ->
              Alaja.print_success("Database ready")

            {_, _} ->
              Alaja.print_info("Database may already exist — continuing")
          end

          verify_pgvector_remote(host, port, user, password, db_name)
          Alaja.print_raw("\n")
          create_db_and_migrate()
          true

        {:error, reason} ->
          Alaja.print_error("Could not reach PostgreSQL: #{reason}")
          Alaja.print_raw("\n")
          Alaja.print_info("Verify the host/port/credentials and that pg_hba.conf allows your IP.")
          skip_msg()
      end
    end
  end

  defp ask_string(prompt, default) do
    ans =
      Interactive.question("#{prompt}#{if default != "", do: " [#{default}]", else: ""}:", color: :cyan)
      |> String.trim()

    if ans == "", do: default, else: ans
  end

  defp ask_int(prompt, default) do
    ans = ask_string(prompt, to_string(default))

    case Integer.parse(ans) do
      {n, _} -> n
      :error -> default
    end
  end

  defp ask_secret(prompt, default) do
    Alaja.print_raw("  #{prompt}: ")
    pw = IO.gets("") |> String.trim()
    if pw == "", do: default, else: pw
  end

  defp update_db_config(overrides) do
    # Merge overrides into Application env for Delfos.Repo. The config file
    # is rewritten in create_db_and_migrate via Manager.write/1.
    base = Application.get_env(:delfos, Delfos.Repo, [])

    new =
      base
      |> Keyword.put(:hostname, overrides["host"])
      |> Keyword.put(:port, overrides["port"])
      |> Keyword.put(:username, overrides["user"])
      |> Keyword.put(:password, overrides["password"])
      |> Keyword.put(:database, overrides["database"])

    Application.put_env(:delfos, Delfos.Repo, new)
    :ok
  end

  defp verify_pgvector_remote(host, port, user, password, db_name) do
    Alaja.print_info("Checking pgvector extension...")

    case System.cmd("psql",
           ["-h", host, "-p", to_string(port), "-U", user, "-d", db_name,
            "-c", "SELECT extversion FROM pg_extension WHERE extname = 'vector'"],
           stderr_to_stdout: true,
           env: [{"PGPASSWORD", password}]
         ) do
      {out, 0} ->
        if String.contains?(out, "0.") do
          Alaja.print_success("pgvector is installed")
        else
          Alaja.print_error("pgvector not installed on remote server")
          Alaja.print_raw("  Ask the server admin to run:\n")
          Alaja.print_raw("  psql -d #{db_name} -c 'CREATE EXTENSION vector;'\n")
        end

      {err, _} ->
        Alaja.print_warning("Could not verify pgvector: #{String.trim(err)}")
    end
  end
end
