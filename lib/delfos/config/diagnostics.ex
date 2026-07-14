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
        results

      {:error, reason} ->
        [
          %{
            id: :diagnostics,
            name: "Diagnostics",
            status: :error,
            message: "runner failed: #{reason}"
          }
        ]
    end
  end

  @doc """
  Returns a human-readable summary string suitable for CLI output.
  """
  @spec summary() :: String.t()
  def summary do
    results = run()
    pass = Enum.count(results, &(&1.status == :ok))
    fail = Enum.count(results, &(&1.status == :error))
    warn = Enum.count(results, &(&1.status == :warning))

    header = "Delfos diagnostic summary: #{pass} passed, #{fail} failed, #{warn} warnings"

    icon_lines =
      Enum.map(results, fn r ->
        icon =
          case r.status do
            :ok -> "✓"
            :error -> "✗"
            :warning -> "!"
          end

        "  #{icon} #{r.name}: #{r.message}"
      end)

    Enum.join([header | icon_lines], "\n")
  end

  # ── Botica check definitions ──────────────────────────────────────────

  @doc "Returns the list of check definitions for Botica.Doctor. Used by doctor.ex for fixes."
  def check_definitions do
    static_checks = [
      %{
        id: :config_file,
        name: "Config file",
        priority: 10,
        fix: &fix_config_file/0,
        fix_command: "delfos doctor --fix",
        check: fn -> do_config_file() end
      },
      %{
        id: :encryption_key,
        name: "Encryption key",
        priority: 20,
        fix: &fix_encryption_key/0,
        fix_command: "delfos doctor --fix",
        check: fn -> do_encryption_key() end
      },
      %{
        id: :postgres_installation,
        name: "PostgreSQL installation",
        priority: 30,
        fix: &fix_postgres_installation/0,
        fix_command: "docker run -d ...  (o instalar PostgreSQL local)",
        check: fn -> do_postgres_installation() end
      },
      %{
        id: :database,
        name: "Database",
        priority: 40,
        fix: &fix_database/0,
        fix_command: "delfos config setup db",
        check: fn -> do_database() end
      },
      %{
        id: :pgvector,
        name: "pgvector extension",
        priority: 50,
        fix: &fix_pgvector/0,
        fix_command: "CREATE EXTENSION vector",
        check: fn -> do_pgvector() end
      },
      %{
        id: :migrations,
        name: "Migrations",
        priority: 60,
        fix: &fix_migrations/0,
        fix_command: "delfos doctor --fix",
        check: fn -> do_migrations() end
      }
    ]

    static_checks ++ provider_checks()
  end

  # ── Fix functions (para Botica.Doctor.fix/1) ──────────────────────────

  defp fix_config_file do
    case Delfos.Config.Manager.ensure_config_exists_public() do
      :ok -> {:ok, "config file regenerated"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fix_encryption_key do
    case Delfos.Config.Manager.ensure_encryption_key() do
      :ok -> {:ok, "encryption key generated"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fix_postgres_installation do
    Delfos.Config.PostgresDiscovery.Installer.install()
  end

  defp fix_database do
    case Delfos.Config.Bootstrap.ensure_database(yes: true) do
      :ok -> {:ok, "database reached"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fix_pgvector do
    case Delfos.Config.Bootstrap.enable_pgvector() do
      :ok -> {:ok, "pgvector enabled"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fix_migrations do
    case Delfos.Config.Bootstrap.ensure_database(yes: true) do
      :ok -> {:ok, "bootstrap applied"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  # ── Provider check factory ────────────────────────────────────────────
  #
  # Collects all configured model endpoints, deduplicates by URL, and
  # returns one Botica check per unique endpoint.
  #
  # Mandatory: embedding, llm
  # Optional:  summarize (if [summarize] section exists)
  #            thinker   (if thinker_url is configured and != llm.url)

  defp provider_checks do
    llm_cfg = Config.Manager.llm()
    llm_url = llm_cfg[:url]

    targets =
      [
        {:embed_provider, Config.Manager.embedding(), 70},
        {:llm_provider, llm_cfg, 80}
      ] ++
        if(sum_cfg = Config.Manager.summarize(),
          do: [{:summarize_provider, sum_cfg, 75}],
          else: []
        ) ++
        if(thinker_configured?(llm_cfg, llm_url),
          do: [
            {:thinker_provider,
             [
               url: llm_cfg[:thinker_url],
               model: llm_cfg[:thinker_model] || "thinker",
               api_key: llm_cfg[:api_key],
               timeout_ms: llm_cfg[:timeout_ms]
             ], 85}
          ],
          else: []
        )

    targets
    |> Enum.uniq_by(fn {_id, cfg, _prio} -> cfg[:url] end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{id, cfg, base_prio}, idx} ->
      build_provider_check(id, cfg, base_prio + idx)
    end)
  end

  defp thinker_configured?(llm_cfg, llm_url) do
    url = llm_cfg[:thinker_url]
    url not in [nil, ""] and url != llm_url
  end

  defp build_provider_check(id, cfg, priority) do
    url = cfg[:url] || ""
    model = cfg[:model] || "model"
    api_key = cfg[:api_key]
    timeout = cfg[:timeout_ms]

    %{
      id: id,
      name: "Provider #{model}",
      priority: priority,
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
