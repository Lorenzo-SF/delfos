defmodule Delfos.Config.Diagnostics do
  @moduledoc """
  Runs a suite of diagnostic checks and returns a structured report.

  Consolidates health checks that were previously scattered across
  `Delfos.Health`, `Delfos.CLI.Commands.Doctor`, and
  `Delfos.CLI.Commands.Setup`. This module is the single source of truth
  for answering "what's wrong with my Delfos setup?"

  Checks performed:
    - Database connectivity (PostgreSQL reachable + migratons up)
    - LLM provider reachable (Embed + Chat endpoints)
    - Index health (project count, embedding coverage, cycles)
    - Config file integrity (valid JSON, encryption key exists)
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
    [
      check_config_file(),
      check_encryption_key(),
      check_postgres_installation(),
      check_database(),
      check_pgvector_extension(),
      check_migrations(),
      check_embed_provider(),
      check_llm_provider()
    ]
    |> List.flatten()
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

    # Bug #8 fix: antes el código hacía `[acc, "  ✓ ..."]` dentro del
    # reduce, lo que producía una lista anidada (cada elemento era
    # `[lista_previa, nuevo_string]`). Enum.join sobre esa estructura
    # fallaba silenciosamente, juntando todos los checks en una sola
    # línea. Ahora construimos la lista de iconos con Enum.map (lista
    # plana) y juntamos con newlines explícitos.
    Enum.join([header | icon_lines], "\n")
  end

  # ── Individual checks ───────────────────────────────────────────────

  defp check_config_file do
    if File.exists?(Config.Manager.config_file()) do
      case File.read(Config.Manager.config_file()) do
        {:ok, content} when content != "" ->
          case Jason.decode(content) do
            {:ok, _} ->
              %{
                status: :pass,
                label: "Config file",
                detail: "Valid JSON at #{Config.Manager.config_file()}"
              }

            {:error, _} ->
              %{
                status: :fail,
                label: "Config file",
                detail: "Corrupt JSON",
                action: "Run: delfos config init"
              }
          end

        _ ->
          %{
            status: :fail,
            label: "Config file",
            detail: "Empty file",
            action: "Run: delfos config init"
          }
      end
    else
      %{
        status: :fail,
        label: "Config file",
        detail: "Not found",
        action: "Run: delfos config init"
      }
    end
  end

  defp check_encryption_key do
    key_file = Path.join(Config.Manager.config_file() |> Path.dirname(), ".key")

    if File.exists?(key_file) do
      case File.read(key_file) do
        {:ok, hex} when byte_size(hex) >= 32 ->
          %{status: :pass, label: "Encryption key", detail: "Present"}

        _ ->
          %{
            status: :fail,
            label: "Encryption key",
            detail: "Corrupt or too short",
            action: "Delete .key and re-run setup"
          }
      end
    else
      %{
        status: :warn,
        label: "Encryption key",
        detail: "Not found — will be created on first write"
      }
    end
  end

  defp check_database do
    case Probe.check_db() do
      :ok ->
        %{status: :pass, label: "Database", detail: "PostgreSQL reachable"}

      {:error, reason} ->
        %{
          status: :fail,
          label: "Database",
          detail: reason,
          action: "Run: delfos doctor --fix (offers Docker install)"
        }
    end
  end

  defp check_postgres_installation do
    servers = PostgresDiscovery.discover()

    case servers do
      [] ->
        %{
          status: :fail,
          label: "PostgreSQL installation",
          detail: "No local or Docker PostgreSQL found",
          action: "Run: delfos doctor --fix (installs Docker postgres-17 + pgvector)"
        }

      [first | _] ->
        kind_str =
          case first.kind do
            :running -> "running on #{first.host}:#{first.port}"
            {:local, v} -> "installed locally (#{v})"
            {:docker, name, image} -> "Docker container '#{name}' (#{image})"
          end

        %{
          status: :pass,
          label: "PostgreSQL installation",
          detail: "Found #{length(servers)} instance(s); using #{kind_str}"
        }
    end
  end

  defp check_pgvector_extension do
    case Repo.query("SELECT extname FROM pg_extension WHERE extname='vector'") do
      {:ok, %{rows: [["vector"]]}} ->
        %{status: :pass, label: "pgvector extension", detail: "Enabled"}

      {:ok, _} ->
        %{
          status: :fail,
          label: "pgvector extension",
          detail: "Not installed",
          action: "Run: delfos doctor --fix (enables extension automatically)"
        }

      {:error, _} ->
        %{status: :warn, label: "pgvector extension", detail: "Cannot check — DB unreachable"}
    end
  rescue
    _e in [DBConnection.ConnectionError] ->
      %{status: :warn, label: "pgvector extension", detail: "Cannot check — DB unreachable"}
  end

  defp check_migrations do
    case Repo.query("SELECT COUNT(*) FROM schema_migrations") do
      {:ok, %{rows: [[count]]}} ->
        %{status: :pass, label: "Migrations", detail: "#{count} applied"}

      {:error, _} ->
        %{
          status: :fail,
          label: "Migrations",
          detail: "Not applied",
          action: "Run: delfos doctor --fix"
        }
    end
  rescue
    _e in [DBConnection.ConnectionError] ->
      %{status: :warn, label: "Migrations", detail: "Cannot check — DB unreachable"}
  end

  defp check_embed_provider do
    cfg = Config.Manager.embedding()
    Probe.check_provider(cfg[:url], cfg[:model], cfg[:api_key], cfg[:timeout_ms])
  end

  defp check_llm_provider do
    cfg = Config.Manager.llm()
    Probe.check_provider(cfg[:url], cfg[:model], cfg[:api_key], cfg[:timeout_ms])
  end
end
