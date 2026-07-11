defmodule Delfos.Config.Diagnostics do
  @moduledoc """
  Runs a suite of diagnostic checks and returns a structured report.

  Powered by Botica.Doctor for parallel execution, timeouts, and
  exception safety.

  Checks performed:
    - Config file integrity (valid JSON, encryption key exists)
    - PostgreSQL availability (installation, connectivity, pgvector, migrations)
    - LLM provider reachable (Embed + Chat endpoints)
  """

  alias Delfos.{Repo, Config}
  alias Delfos.Config.Probe
  alias Delfos.Config.PostgresDiscovery

  @typedoc """
  Diagnostic result for a single check.
  """
  @type check_result :: %{
          required(:status) => :pass | :fail | :warn,
          required(:label) => String.t(),
          required(:detail) => String.t(),
          optional(:action) => String.t()
        }

  @doc """
  Runs all checks and returns a list of results.
  """
  @spec run() :: [check_result()]
  def run do
    config = %{
      app_name: "delfos",
      checks: check_definitions()
    }

    case Botica.Doctor.run(config) do
      {:ok, results} ->
        Enum.map(results, &to_legacy/1)

      {:error, reason} ->
        [%{status: :fail, label: "Diagnostics", detail: "runner failed: #{reason}"}]
    end
  end

  @doc """
  Returns a human-readable summary string suitable for CLI output.
  """
  @spec summary() :: String.t()
  def summary do
    results = run()
    pass = Enum.count(results, &(&1.status == :pass))
    fail = Enum.count(results, &(&1.status == :fail))
    warn = Enum.count(results, &(&1.status == :warn))

    header = "Delfos diagnostic summary: #{pass} passed, #{fail} failed, #{warn} warnings"

    icon_lines =
      Enum.map(results, fn r ->
        icon =
          case r.status do
            :pass -> "✓"
            :fail -> "✗"
            :warn -> "!"
          end

        "  #{icon} #{r.label}: #{r.detail}"
      end)

    Enum.join([header | icon_lines], "\n")
  end

  # ── Botica check definitions ──────────────────────────────────────────

  defp check_definitions do
    [
      %{
        id: :config_file,
        name: "Config file",
        priority: 10,
        fix: nil,
        check: fn -> do_config_file() end
      },
      %{
        id: :encryption_key,
        name: "Encryption key",
        priority: 20,
        fix: nil,
        check: fn -> do_encryption_key() end
      },
      %{
        id: :postgres_installation,
        name: "PostgreSQL installation",
        priority: 30,
        fix: nil,
        check: fn -> do_postgres_installation() end
      },
      %{
        id: :database,
        name: "Database",
        priority: 40,
        fix: nil,
        check: fn -> do_database() end
      },
      %{
        id: :pgvector,
        name: "pgvector extension",
        priority: 50,
        fix: nil,
        check: fn -> do_pgvector() end
      },
      %{
        id: :migrations,
        name: "Migrations",
        priority: 60,
        fix: nil,
        check: fn -> do_migrations() end
      },
      provider_check(:embedding),
      provider_check(:llm)
    ]
  end

  # ── Transform Botica result → legacy map format ───────────────────────

  defp to_legacy(%{id: id, name: name, status: status, message: msg}) do
    %{
      status: translate_status(status),
      label: name,
      detail: msg,
      action: action_for(id)
    }
  end

  defp translate_status(:ok), do: :pass
  defp translate_status(:warning), do: :warn
  defp translate_status(:error), do: :fail

  defp action_for(:config_file), do: "Run: delfos config init"
  defp action_for(:encryption_key), do: "Delete .key and re-run setup"

  defp action_for(:postgres_installation),
    do: "Run: delfos doctor --fix (installs Docker postgres-17 + pgvector)"

  defp action_for(:database),
    do: "Run: delfos doctor --fix (offers Docker install)"

  defp action_for(:pgvector),
    do: "Run: delfos doctor --fix (enables extension automatically)"

  defp action_for(:migrations), do: "Run: delfos doctor --fix"
  defp action_for(_), do: nil

  # ── Provider check factory ────────────────────────────────────────────
  #
  # Each provider check has a dynamic name ("Provider <model>") so the
  # Doctor command's fix dispatch (%{label: "Provider " <> _}) keeps
  # working. The recovery hint from Probe.check_provider/4 is appended
  # to the error message.

  defp provider_check(:embedding) do
    cfg = Config.Manager.embedding()
    url = cfg[:url] || ""
    model = cfg[:model] || "embedding"
    api_key = cfg[:api_key]
    timeout = cfg[:timeout_ms]

    %{
      id: :embed_provider,
      name: "Provider #{model}",
      priority: 70,
      fix: nil,
      check: fn ->
        case Probe.check_provider(url, model, api_key, timeout) do
          %{status: :pass, detail: msg} -> {:ok, msg}
          %{status: :fail, detail: msg, action: action} -> {:error, "#{msg} — #{action}"}
          %{status: :fail, detail: msg} -> {:error, msg}
        end
      end
    }
  end

  defp provider_check(:llm) do
    cfg = Config.Manager.llm()
    url = cfg[:url] || ""
    model = cfg[:model] || "llm"
    api_key = cfg[:api_key]
    timeout = cfg[:timeout_ms]

    %{
      id: :llm_provider,
      name: "Provider #{model}",
      priority: 80,
      fix: nil,
      check: fn ->
        case Probe.check_provider(url, model, api_key, timeout) do
          %{status: :pass, detail: msg} -> {:ok, msg}
          %{status: :fail, detail: msg, action: action} -> {:error, "#{msg} — #{action}"}
          %{status: :fail, detail: msg} -> {:error, msg}
        end
      end
    }
  end

  # ── Individual check implementations ──────────────────────────────────
  #
  # All return {:ok, msg} | {:warning, msg} | {:error, msg} for Botica.

  defp do_config_file do
    if File.exists?(Config.Manager.config_file()) do
      case File.read(Config.Manager.config_file()) do
        {:ok, content} when content != "" ->
          case Jason.decode(content) do
            {:ok, _} -> {:ok, "Valid JSON at #{Config.Manager.config_file()}"}
            {:error, _} -> {:error, "Corrupt JSON"}
          end

        _ ->
          {:error, "Empty file"}
      end
    else
      {:error, "Not found"}
    end
  end

  defp do_encryption_key do
    key_file = Path.join(Config.Manager.config_file() |> Path.dirname(), ".key")

    if File.exists?(key_file) do
      case File.read(key_file) do
        {:ok, hex} when byte_size(hex) >= 32 -> {:ok, "Present"}
        _ -> {:error, "Corrupt or too short"}
      end
    else
      {:warning, "Not found — will be created on first write"}
    end
  end

  defp do_postgres_installation do
    servers = PostgresDiscovery.discover()

    case servers do
      [] ->
        {:error, "No local or Docker PostgreSQL found"}

      [first | _] ->
        kind_str =
          case first.kind do
            :running -> "running on #{first.host}:#{first.port}"
            {:local, v} -> "installed locally (#{v})"
            {:docker, name, image} -> "Docker container '#{name}' (#{image})"
          end

        {:ok, "Found #{length(servers)} instance(s); using #{kind_str}"}
    end
  end

  defp do_database do
    case Probe.check_db() do
      :ok -> {:ok, "PostgreSQL reachable"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_pgvector do
    case Repo.query("SELECT extname FROM pg_extension WHERE extname='vector'") do
      {:ok, %{rows: [["vector"]]}} -> {:ok, "Enabled"}
      {:ok, _} -> {:error, "Not installed"}
      {:error, _} -> {:warning, "Cannot check — DB unreachable"}
    end
  rescue
    _e in [DBConnection.ConnectionError] -> {:warning, "Cannot check — DB unreachable"}
  end

  defp do_migrations do
    case Repo.query("SELECT COUNT(*) FROM schema_migrations") do
      {:ok, %{rows: [[count]]}} -> {:ok, "#{count} applied"}
      {:error, _} -> {:error, "Not applied"}
    end
  rescue
    _e in [DBConnection.ConnectionError] ->
      {:warning, "Cannot check — DB unreachable"}
  end
end
