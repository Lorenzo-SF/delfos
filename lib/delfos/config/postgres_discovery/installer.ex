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
    case System.find_executable("docker") do
      nil ->
        raise """
        Docker is not installed. Install it from https://docs.docker.com/get-docker/ \
        and run 'delfos doctor --fix' again.
        """

      _path ->
        case System.cmd("docker", ["version", "--format", "{{.Server.Version}}"]) do
          {_, 0} -> :ok
          _ -> raise "Docker is installed but the daemon is unreachable."
        end
    end
  end

  defp ensure_image! do
    Alaja.print_info("Pulling #{@image} (this can take a minute)...")

    case System.cmd("docker", ["pull", @image]) do
      {_, 0} -> :ok
      {out, code} -> raise "docker pull failed (#{code}): #{out}"
    end
  end

  defp start_or_create! do
    case inspect_container() do
      {:running, _} ->
        Alaja.print_info("Container '#{@container_name}' is already running.")

      {:stopped, _} ->
        Alaja.print_info("Starting existing container '#{@container_name}'...")
        run!(["start", @container_name])

      :missing ->
        Alaja.print_info("Creating new container '#{@container_name}'...")
        create_container()
    end
  end

  defp create_container do
    args = [
      "run",
      "-d",
      "--name",
      @container_name,
      "-p",
      "127.0.0.1:#{@port}:5432",
      "-e",
      "POSTGRES_USER=#{@user}",
      "-e",
      "POSTGRES_PASSWORD=#{@password}",
      "-e",
      "POSTGRES_DB=delfos_prod",
      "-v",
      "#{@volume}:/var/lib/postgresql/data",
      "--restart",
      "unless-stopped",
      @image
    ]

    run!(args)
  end

  defp wait_until_ready! do
    Alaja.print_info("Waiting for PostgreSQL to accept connections...")

    1..30
    |> Enum.reduce_while(:timeout, fn i, _ ->
      Process.sleep(1_000)

      if port_open?("127.0.0.1", @port, 500) do
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
      run!(
        [
          "exec",
          "-u",
          @user,
          @container_name,
          "psql",
          "-d",
          "delfos_prod",
          "-tAc",
          "SELECT extname FROM pg_extension WHERE extname='vector';"
        ],
        allowed_exit: [0, 1]
      )

    if String.contains?(output, "vector") do
      Alaja.print_success("pgvector is available.")
    else
      Alaja.print_info("Enabling pgvector extension...")

      run!([
        "exec",
        "-u",
        @user,
        @container_name,
        "psql",
        "-d",
        "delfos_prod",
        "-c",
        "CREATE EXTENSION IF NOT EXISTS vector;"
      ])
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

  # ── Helpers ────────────────────────────────────────────────────────────

  defp inspect_container do
    case System.cmd("docker", [
           "inspect",
           @container_name,
           "--format",
           "{{.State.Running}}"
         ]) do
      {out, 0} ->
        case String.trim(out) do
          "true" -> {:running, nil}
          "false" -> {:stopped, nil}
          _ -> :missing
        end

      _ ->
        :missing
    end
  end

  defp run!(args, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_exit, [0])

    case System.cmd("docker", args) do
      {out, code} ->
        if Enum.member?(allowed, code) do
          out
        else
          raise "docker #{Enum.join(args, " ")} failed (#{code}): #{out}"
        end
    end
  end

  defp port_open?(host, port, timeout_ms) do
    case :gen_tcp.connect(String.to_charlist(host), port, [], timeout_ms) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
