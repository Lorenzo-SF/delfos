defmodule Delfos.Config.PostgresDiscovery do
  @moduledoc """
  Discovers PostgreSQL installations on the local machine.

  Looks in three places, in priority order:
    1. Already-running PostgreSQL servers (via `pg_isready` or `:gen_tcp` probe).
    2. Local installations on standard paths (apt, brew, nix, systemd, …).
    3. Docker containers running `postgres:*` images.

  Returns a list of `Delfos.Config.PostgresDiscovery.Server` structs
  with the connection params Delfos can use. The doctor uses this to
  figure out where to create the database without asking the user
  (unless nothing is found, in which case `install/0` is offered).
  """

  alias Delfos.Config.PostgresDiscovery.{Server, Installer}

  @typedoc """
  Connection params for a discovered PostgreSQL instance.
  """
  @opaque server :: Server.t()

  @doc """
  Returns all PostgreSQL servers reachable on this host.

  Results are sorted by `priority` (lowest first) so the first entry is
  the one Delfos will prefer when auto-configuring.
  """
  @spec discover() :: [server()]
  def discover do
    []
    |> add_running_servers()
    |> add_local_installations()
    |> add_docker_containers()
    |> Enum.uniq_by(& &1.host)
    |> Enum.sort_by(& &1.priority)
  end

  @doc """
  Convenience: returns true if at least one PostgreSQL is reachable.
  """
  @spec available?() :: boolean()
  def available?, do: discover() != []

  @doc """
  Best-effort: returns the host/port of the first reachable server, or `nil`.
  """
  @spec first_reachable() :: {String.t(), pos_integer()} | nil
  def first_reachable do
    case discover() do
      [first | _] -> {first.host, first.port}
      [] -> nil
    end
  end

  # ── Private scanners ──────────────────────────────────────────────────

  defp add_running_servers(acc) do
    candidates = [
      {"127.0.0.1", 5432},
      {"localhost", 5432},
      {"/var/run/postgresql", 5432}
    ]

    acc ++ Enum.flat_map(candidates, &probe_endpoint/1)
  end

  defp probe_endpoint({host, port}) do
    if port_open?(host, port, 500) do
      [Server.new(host, port, :running, 0)]
    else
      []
    end
  end

  defp add_local_installations(acc) do
    paths = [
      "/usr/lib/postgresql",
      "/usr/local/postgresql",
      "/opt/homebrew/opt/postgresql@17",
      "/opt/homebrew/opt/postgresql@16",
      "/opt/homebrew/opt/postgresql@15",
      "/opt/homebrew/opt/postgresql@14",
      "/usr/local/var/postgres",
      "/nix/store"
    ]

    found =
      Enum.flat_map(paths, fn base ->
        if File.dir?(base) do
          versions = list_subdirs(base)
          Enum.flat_map(versions, &probe_version_dir(&1, base))
        else
          []
        end
      end)

    acc ++ found
  end

  defp probe_version_dir(version, base) do
    bindir = Path.join([base, version, "bin"])
    pg_ctl = Path.join(bindir, "pg_ctl")

    if File.exists?(pg_ctl) do
      version_num = parse_version(version)
      priority = if version_num >= 17, do: 1, else: 2

      [
        Server.new(
          "127.0.0.1",
          guess_port_for(version_num) || 5432,
          {:local, version},
          priority
        )
      ]
    else
      []
    end
  end

  defp list_subdirs(base) do
    case File.ls(base) do
      {:ok, names} ->
        Enum.filter(names, fn n -> File.dir?(Path.join(base, n)) end)

      _ ->
        []
    end
  end

  defp parse_version("postgresql@" <> v), do: String.to_integer(v)

  defp parse_version(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp guess_port_for(17), do: 5432
  defp guess_port_for(16), do: 5432
  defp guess_port_for(15), do: 5432
  defp guess_port_for(_), do: 5432

  defp add_docker_containers(acc) do
    if docker_available?() do
      acc ++ list_docker_postgres()
    else
      acc
    end
  end

  defp docker_available? do
    case System.find_executable("docker") do
      nil -> false
      _path -> true
    end
  end

  defp list_docker_postgres do
    case System.cmd("docker", ["ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Ports}}"]) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&parse_docker_line/1)

      _ ->
        []
    end
  end

  defp parse_docker_line(line) do
    case String.split(line, "\t") do
      [name, image, ports] ->
        if String.starts_with?(image, "postgres") do
          port = parse_docker_port(ports) || 5432
          [Server.new("127.0.0.1", port, {:docker, name, image}, 0)]
        else
          []
        end

      _ ->
        []
    end
  end

  defp parse_docker_port(ports) do
    # Format: "0.0.0.0:5432->5432/tcp, ..."
    case Regex.run(~r/(\d+)->5432/, ports) do
      [_, p] -> String.to_integer(p)
      _ -> nil
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

  @doc """
  Asks the user (interactively) whether they want Delfos to install
  PostgreSQL 17 via Docker. Returns `:installed`, `:user_declined`, or
  `{:error, reason}`.

  Use `--yes` to skip the prompt.
  """
  @spec offer_install(keyword()) :: :installed | :user_declined | {:error, term()}
  def offer_install(opts \\ []) do
    auto_yes = Keyword.get(opts, :yes, false)

    if auto_yes or confirm_install?() do
      Installer.install()
    else
      :user_declined
    end
  end

  defp confirm_install? do
    Alaja.print_warning("No PostgreSQL installation found on this machine.")

    Alaja.print_raw("""

    Delfos needs PostgreSQL 17 (with pgvector) to function. The easiest
    way to get one is via Docker — it's portable, isolated, and reversible.

    """)

    case Alaja.Printer.Interactive.question_with_options(
           "Install PostgreSQL 17 + pgvector via Docker now?",
           [{"Yes", :yes}, {"No", :no}]
         ) do
      :yes -> true
      :no -> false
      _ -> false
    end
  rescue
    _ -> false
  end
end
