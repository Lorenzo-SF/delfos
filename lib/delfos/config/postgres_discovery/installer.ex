defmodule Delfos.Config.PostgresDiscovery.Installer do
  @moduledoc """
  Installs PostgreSQL 17 with pgvector inside a Docker container.

  This is the path of least surprise: Docker is portable, isolated,
  reversible, and ships its own persistent volume. The container is
  exposed on `127.0.0.1:5432` so the rest of Delfos can use it without
  any additional config.

  ## Why Docker and not a system install?

  System installs require `sudo`, conflict with anything the user has
  already configured, and need manual setup of `pg_hba.conf`,
  `postgresql.conf`, the `postgres` user, and the `pgvector` extension.
  Docker gives us a single command that does all of it.
  """

  alias Alaja

  alias Trebejo.Docker, as: Docker
  alias Trebejo.Network, as: Network

  @container_name "delfos-postgres"
  @image "pgvector/pgvector:pg17"
  @volume "delfos-pgdata"
  @port 5432
  @user "delfos"
  @password "delfos"

  @doc """
  Creates and starts the Delfos PostgreSQL container.

  Idempotent: if a container with the same name is already running, returns
  `:already_running`. If the container exists but is stopped, starts it.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec install() :: :ok | {:error, String.t()}
  def install do
    ensure_docker!()
    ensure_image!()
    start_or_create!()
    wait_until_ready!()
    verify_pgvector!()
    configure_delfos_config()
    :ok
  end

  @doc """
  Returns the connection params the rest of Delfos should use.
  """
  @spec connection_params() :: keyword()
  def connection_params do
    [
      hostname: "127.0.0.1",
      port: @port,
      username: @user,
      password: @password,
      database: "delfos_prod"
    ]
  end

  # ── Steps ───────────────────────────────────────────────────────────────

  defp ensure_docker! do
    case Docker.runtime() do
      :none ->
        raise """
        Docker is not installed. Install it from https://docs.docker.com/get-docker/ \
        and run 'delfos doctor --fix' again.
        """

      _ ->
        :ok
    end
  end

  defp ensure_image! do
    Alaja.print_info("Pulling #{@image} (this can take a minute)...")

    case Docker.pull(@image) do
      :ok -> :ok
      {:error, reason} -> raise "docker pull failed: #{reason}"
    end
  end

  defp start_or_create! do
    case Docker.state(@container_name) do
      :running ->
        Alaja.print_info("Container '#{@container_name}' is already running.")

      :stopped ->
        Alaja.print_info("Starting existing container '#{@container_name}'...")

        case Docker.start(@container_name) do
          :ok -> :ok
          {:error, reason} -> raise "docker start failed: #{reason}"
        end

      :missing ->
        Alaja.print_info("Creating new container '#{@container_name}'...")
        create_container()
    end
  end

  defp create_container do
    case Docker.run(
           name: @container_name,
           image: @image,
           ports: ["127.0.0.1:#{@port}:5432"],
           env: [
             "POSTGRES_USER=#{@user}",
             "POSTGRES_PASSWORD=#{@password}",
             "POSTGRES_DB=delfos_prod"
           ],
           volume: ["#{@volume}:/var/lib/postgresql/data"],
           restart: "unless-stopped",
           detach: true
         ) do
      {:ok, _container_id} -> :ok
      {:error, reason} -> raise "docker run failed: #{reason}"
    end
  end

  defp wait_until_ready! do
    Alaja.print_info("Waiting for PostgreSQL to accept connections...")

    1..30
    |> Enum.reduce_while(:timeout, fn i, _ ->
      Process.sleep(1_000)

      if Network.port_open?("127.0.0.1", @port, timeout: 500) do
        {:ok, :ready}
      else
        Alaja.print_raw(".")

        if i == 30 do
          {:halt, :timeout}
        else
          {:cont, :timeout}
        end
      end
    end)
    |> case do
      :ok -> :ok
      :timeout -> raise "PostgreSQL did not become reachable within 30s."
    end

    # Extra wait for PG to actually accept auth connections.
    Process.sleep(1_000)
  end

  defp verify_pgvector! do
    Alaja.print_info("Verifying pgvector extension...")

    output =
      case Docker.exec(
             @container_name,
             [
               "psql",
               "-d",
               "delfos_prod",
               "-tAc",
               "SELECT extname FROM pg_extension WHERE extname='vector';"
             ], user: @user) do
        {:ok, out} -> out
        {:error, _reason} -> ""
      end

    if String.contains?(output, "vector") do
      Alaja.print_success("pgvector is available.")
    else
      Alaja.print_info("Enabling pgvector extension...")

      Docker.exec(
        @container_name,
        [
          "psql",
          "-d",
          "delfos_prod",
          "-c",
          "CREATE EXTENSION IF NOT EXISTS vector;"
        ], user: @user)
    end
  end

  defp configure_delfos_config do
    Delfos.Config.Manager.write(%{
      "embedding" => %{
        "provider" => "local",
        "url" => "http://127.0.0.1:9998",
        "model" => "mxbai-embed-v1",
        "dim" => 4096,
        "api_key" => "sk-local-dev"
      },
      "llm" => %{
        "provider" => "local",
        "url" => "http://127.0.0.1:8080",
        "model" => "thinker",
        "api_key" => "sk-local-dev"
      },
      "database" => %{
        "hostname" => "127.0.0.1",
        "port" => @port,
        "username" => @user,
        "password" => @password,
        "database" => "delfos_prod"
      }
    })

    Alaja.print_success("Wrote config: #{Delfos.Config.Manager.config_file()}")
  end
end
