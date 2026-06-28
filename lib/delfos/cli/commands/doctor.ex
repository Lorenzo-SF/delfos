defmodule Delfos.CLI.Commands.Doctor do
  @moduledoc """
  Full diagnostic of the Delfos environment.

  With `--fix` attempts to repair detected issues. With `--interactive`
  asks the user before applying any fix that touches the database or
  external services.

  ## What it checks

    1. Config file (`~/.config/delfos/delfos.conf`)
    2. PostgreSQL connection (host, port, credentials, network)
    3. pgvector extension (installed, version)
    4. Embedding endpoint reachable + dimension matches config
    5. LLM endpoint reachable + responds
    6. Tree-sitter NIF (compilation status)

  Output is rendered through `Alaja` so check results get icon-prefixed
  messages and an end-of-run summary.
  """

  import Ecto.Query
  alias Alaja
  alias Delfos.{Repo, Schema}
  alias Delfos.Config.Manager
  # Schema is referenced via Delfos.Schema.* in queries — keep alias for clarity
  _ = Schema

  @help """
  USAGE
      delfos doctor [flags]

  FLAGS
      --fix            Attempt to repair detected issues automatically
      --interactive    Ask before applying each fix (recommended for first run)
      --db-only        Only run PostgreSQL/pgvector checks (skip LLM/NIF)
      --llm-only       Only run embedding/LLM endpoint checks
      --json           Output results as JSON (machine-readable)

  EXAMPLES
      delfos doctor
      delfos doctor --fix --interactive
      delfos doctor --db-only
      delfos doctor --json | jq '.results[] | select(.status=="error")'

  For full Delfos setup see:
      https://github.com/Lorenzo-SF/delfos#quick-start
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          fix: :boolean,
          interactive: :boolean,
          db_only: :boolean,
          llm_only: :boolean,
          json: :boolean
        ]
      )

    fix_mode = opts[:fix] || false
    interactive = opts[:interactive] || false
    db_only = opts[:db_only] || false
    llm_only = opts[:llm_only] || false
    json_mode = opts[:json] || false

    if json_mode do
      run_json(fix_mode, interactive, db_only, llm_only)
    else
      run_pretty(fix_mode, interactive, db_only, llm_only)
    end
  end

  # ---------------------------------------------------------------------------
  # Pretty (default) mode
  # ---------------------------------------------------------------------------

  defp run_pretty(fix_mode, interactive, db_only, llm_only) do
    banner =
      if fix_mode,
        do: "\n=== DELFOS DOCTOR — fix mode ===\n\n",
        else: "\n=== DELFOS DOCTOR ===\n\n"

    Alaja.print_raw(banner)

    config = build_doctor_config(db_only, llm_only)

    if fix_mode do
      Alaja.print_info("Running fixes (interactive=#{interactive})...\n")

      {:ok, results} = Botica.Doctor.run(config)

      report =
        if interactive do
          run_interactive_fixes(config, results)
        else
          {:ok, report} = Botica.Repair.Fixer.fix(config, results)
          report
        end

      print_fix_report(report)

      Alaja.print_raw("\nPost-fix verification:\n\n")
    end

    {:ok, results} = Botica.Doctor.run(config)
    print_results(results)

    summary = Botica.Doctor.summary(results)
    print_summary(summary)
    check_index_health()

    if summary.error > 0, do: System.halt(1)
  end

  defp run_interactive_fixes(config, results) do
    Enum.reduce(results, initial_report(), fn result, report ->
      apply_interactive_fix(config, result, report)
    end)
  end

  defp initial_report, do: %{applied: [], failed: [], skipped: []}

  defp apply_interactive_fix(_config, result, report) when result.status == :ok do
    report
  end

  defp apply_interactive_fix(config, result, report) do
    check_def = Enum.find(config.checks, &(&1.id == result.id))

    cond do
      is_nil(check_def) or is_nil(check_def[:fix]) ->
        %{report | skipped: [result.id | report.skipped]}

      ask_user("Apply fix for '#{result.name}' (#{result.message})? [s/N]") ->
        apply_fix(check_def, report)

      true ->
        %{report | skipped: [result.id | report.skipped]}
    end
  end

  defp apply_fix(check_def, report) do
    Alaja.print_info("Applying fix for #{check_def.id}...")

    case check_def[:fix].() do
      {:ok, msg} ->
        Alaja.print_success("Fixed: #{msg}")
        %{report | applied: [check_def.id | report.applied]}

      {:error, reason} ->
        Alaja.print_error("Fix failed: #{reason}")
        %{report | failed: [{check_def.id, reason} | report.failed]}

      :skipped ->
        %{report | skipped: [check_def.id | report.skipped]}
    end
  end

  defp ask_user(prompt) do
    Alaja.print_info("  #{prompt} ")
    ans = IO.gets("") |> String.trim() |> String.downcase()
    ans in ["s", "si", "sí", "y", "yes"]
  end

  defp run_json(fix_mode, _interactive, db_only, llm_only) do
    config = build_doctor_config(db_only, llm_only)

    if fix_mode do
      {:ok, results} = Botica.Doctor.run(config)
      {:ok, report} = Botica.Repair.Fixer.fix(config, results)
      IO.puts(Jason.encode!(%{results: results, fix_report: report}, pretty: true))
    else
      {:ok, results} = Botica.Doctor.run(config)

      IO.puts(
        Jason.encode!(%{results: results, summary: Botica.Doctor.summary(results)}, pretty: true)
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Check definitions
  # ---------------------------------------------------------------------------

  defp build_doctor_config(db_only, llm_only) do
    cfg_emb = Manager.embedding()
    cfg_llm = Manager.llm()

    checks =
      []
      |> maybe_add_checks(
        [
          build_config_file_check(),
          build_postgresql_check(),
          build_pgvector_check()
        ],
        db_only,
        :db
      )
      |> maybe_add_checks(
        [
          build_embedding_check(cfg_emb),
          build_llm_check(cfg_llm),
          build_anthropic_embedding_warning(cfg_emb)
        ],
        llm_only,
        :llm
      )
      |> maybe_add_check(build_tree_sitter_check(), db_only or llm_only)

    %{
      app_name: "delfos",
      checks: checks
    }
  end

  # If db_only is set, only include db-side checks; if llm_only, only llm-side;
  # if neither, include all. tree_sitter is included unless either filter is on.
  defp maybe_add_checks(checks, candidates, only?, side) do
    cond do
      only? == false -> checks ++ candidates
      side == :db and only? -> checks ++ Enum.take(candidates, 2)
      side == :llm and only? -> checks ++ Enum.drop(candidates, 2)
      true -> checks
    end
  end

  defp maybe_add_check(checks, _check, true), do: checks
  defp maybe_add_check(checks, check, false), do: checks ++ [check]

  # -- 1. Config file -------------------------------------------------------

  defp build_config_file_check do
    %{
      id: :config_file,
      name: "Config file",
      description: Manager.config_file(),
      priority: 1,
      tags: [:config],
      timeout: 2_000,
      check: fn ->
        path = Manager.config_file()

        cond do
          not File.exists?(path) ->
            {:warning, "Not found at #{path}"}

          true ->
            case Toml.decode_file(path) do
              {:ok, _} -> {:ok, path}
              {:error, reason} -> {:error, "Invalid TOML: #{inspect(reason)}"}
            end
        end
      end,
      fix: fn ->
        path = Manager.config_file()
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Manager.default_config_content())
        {:ok, "Created #{path} with defaults"}
      end,
      fix_command: "delfos config init"
    }
  end

  # -- 2. PostgreSQL --------------------------------------------------------

  defp build_postgresql_check do
    %{
      id: :postgresql,
      name: "PostgreSQL",
      description: db_target_description(),
      priority: 2,
      tags: [:database],
      timeout: 5_000,
      check: fn ->
        # Build Repo on the fly using the same DB config as the application
        # but allow the user to override via env vars explicitly.
        case connect_with_overrides() do
          :ok ->
            case Repo.query("SELECT version()") do
              {:ok, %{rows: [[ver]]}} ->
                short = String.slice(ver, 0, 80)
                {:ok, short}

              {:error, reason} ->
                {:error, "Query failed: #{format_db_error(reason)}"}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end,
      fix: fn ->
        Alaja.print_info("PostgreSQL cannot be auto-installed. Check the connection details:")

        Alaja.print_raw(db_target_description() <> "\n")
        Alaja.print_info("Common causes:")
        Alaja.print_raw("  - DB_HOST/DB_USER/DB_PASS not exported in this shell\n")
        Alaja.print_raw("  - PostgreSQL not running locally (docker? systemd? remote?)\n")
        Alaja.print_raw("  - Firewall blocking the port\n")
        {:ok, "manual intervention required"}
      end,
      fix_command: nil
    }
  end

  # -- 3. pgvector ----------------------------------------------------------

  defp build_pgvector_check do
    %{
      id: :pgvector,
      name: "pgvector extension",
      description: "Required for vector similarity search",
      priority: 3,
      tags: [:database],
      timeout: 5_000,
      check: fn ->
        case Repo.query("SELECT extversion FROM pg_extension WHERE extname = 'vector'") do
          {:ok, %{rows: [[v]]}} -> {:ok, "v#{v}"}
          {:ok, %{rows: []}} -> {:error, "Extension not installed in current database"}
          {:error, reason} -> {:error, "Cannot query extensions: #{format_db_error(reason)}"}
        end
      end,
      fix: fn ->
        case Repo.query("CREATE EXTENSION IF NOT EXISTS vector") do
          {:ok, _} ->
            {:ok, "Extension installed"}

          {:error, reason} ->
            {:error, "Cannot auto-install (likely needs superuser): #{format_db_error(reason)}"}
        end
      end,
      fix_command: "psql -d <your_db> -c 'CREATE EXTENSION vector;'"
    }
  end

  # -- 4. Embedding endpoint ------------------------------------------------

  defp build_embedding_check(cfg_emb) do
    %{
      id: :embedding,
      name: "Embedding endpoint (#{cfg_emb[:provider]})",
      description: "#{cfg_emb[:url]} · #{cfg_emb[:model]} · dim=#{cfg_emb[:dim]}",
      priority: 4,
      tags: [:llm],
      timeout: 10_000,
      check: fn -> check_embedding(cfg_emb) end,
      fix: fn ->
        Alaja.print_info("Embedding endpoint not reachable. Verify the server is running:")

        Alaja.print_raw(
          "  llama-server -m #{cfg_emb[:model]}.gguf --port #{port_from_url(cfg_emb[:url])} --embedding ...\n"
        )

        {:ok, "manual intervention required"}
      end,
      fix_command:
        "llama-server -m bge-m3-q4_k_m.gguf --port 9998 --embedding --threads 4 --batch-size 64 --ctx-size 2048 --mlock --no-mmap --flash-attn --host 127.0.0.1"
    }
  end

  # -- 5a. Anthropic embedding warning ---------------------------------------

  defp build_anthropic_embedding_warning(cfg_emb) do
    %{
      id: :anthropic_embedding,
      name: "Anthropic embedding provider",
      description: "Anthropic models are not optimised for embeddings",
      priority: 3,
      tags: [:llm, :config],
      timeout: 500,
      check: fn -> check_anthropic_embedding(cfg_emb) end,
      fix: nil,
      fix_command: nil
    }
  end

  defp check_anthropic_embedding(cfg_emb) do
    provider = cfg_emb[:provider] |> to_string() |> String.downcase()

    if String.contains?(provider, "anthropic") do
      {:warning,
       "Anthropic is not recommended for embeddings. Use text-embedding-3-small (OpenAI) or voyage-2 (Voyage). Set provider=openai in [embedding] section."}
    else
      {:ok, "Embedding provider is #{cfg_emb[:provider]} — no Anthropic warning needed"}
    end
  end

  # -- 5. LLM endpoint ------------------------------------------------------

  defp build_llm_check(cfg_llm) do
    %{
      id: :llm,
      name: "LLM endpoint (#{cfg_llm[:provider]})",
      description: "#{cfg_llm[:url]} · #{cfg_llm[:model]}",
      priority: 5,
      tags: [:llm],
      timeout: 10_000,
      check: fn -> check_llm(cfg_llm) end,
      fix: fn ->
        Alaja.print_info("LLM endpoint not reachable. Verify the server is running:")

        Alaja.print_raw(
          "  llama-server -m <model>.gguf --port #{port_from_url(cfg_llm[:url])} --threads 6 --batch-size 128 --ctx-size 8192 --mlock --no-mmap --flash-attn --host 127.0.0.1\n"
        )

        {:ok, "manual intervention required"}
      end,
      fix_command: nil
    }
  end

  # -- 6. Tree-sitter NIF ---------------------------------------------------

  defp build_tree_sitter_check do
    %{
      id: :tree_sitter,
      name: "Tree-sitter NIF",
      description: "Rust AST parser for precise symbol extraction",
      priority: 6,
      tags: [:nif],
      timeout: 2_000,
      check: fn ->
        try do
          langs = Delfos.Parsers.TreeSitter.NIF.supported_languages()
          {:ok, "#{length(langs)} languages with real AST"}
        rescue
          _ -> {:warning, "NIF not compiled — falling back to GenericParser (regex)"}
        end
      end,
      fix: fn -> :skipped end,
      fix_command: "cd deps/tree_sitter && mix compile"
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp db_target_description do
    host = System.get_env("DB_HOST") || Application.get_env(:delfos, :db_host, "127.0.0.1")
    port = System.get_env("DB_PORT") || Application.get_env(:delfos, :db_port, "5432")
    db_name = System.get_env("DB_NAME") || Application.get_env(:delfos, :db_name, "delfos_dev")
    "PostgreSQL @ #{host}:#{port}/#{db_name}"
  end

  defp connect_with_overrides do
    # Use env overrides if present, otherwise the app config.
    config = Application.get_env(:delfos, Delfos.Repo, [])

    new_config =
      config
      |> maybe_put_env(:hostname, "DB_HOST")
      |> maybe_put_env(:port, "DB_PORT")
      |> maybe_put_env(:database, "DB_NAME")
      |> maybe_put_env(:username, "DB_USER")
      |> maybe_put_env(:password, "DB_PASS")

    if new_config != config do
      Application.put_env(:delfos, Delfos.Repo, new_config)
      Delfos.Repo.start_link()
    end

    :ok
  rescue
    e -> {:error, "Cannot start Repo: #{Exception.message(e)}"}
  end

  defp maybe_put_env(config, key, env_var) do
    case System.get_env(env_var) do
      nil -> config
      value -> Keyword.put(config, key, value)
    end
  end

  defp format_db_error(%Postgrex.Error{} = err) do
    severity = err.postgres[:severity] || "ERROR"
    "#{severity}: #{err.message || inspect(err)}"
  end

  defp format_db_error(reason), do: inspect(reason)

  defp port_from_url(url) when is_binary(url) do
    case Regex.run(~r/:(\d+)/, url) do
      [_, port] -> port
      _ -> "8080"
    end
  end

  defp port_from_url(_), do: "8080"

  # ---------------------------------------------------------------------------
  # Endpoint probes
  # ---------------------------------------------------------------------------

  defp check_embedding(%{provider: :local} = cfg) do
    with {:ok, _} <- http_health(cfg[:url]),
         {:ok, vec} <- Delfos.LLM.Client.embed("test") do
      dim = length(vec)

      if dim == cfg[:dim] do
        {:ok, "OK · dim=#{dim}"}
      else
        {:warning,
         "dim mismatch · returned=#{dim}, config=#{cfg[:dim]}. Run: delfos config set embedding dim #{dim}"}
      end
    else
      err -> {:error, "Local embedding server: #{format_probe_error(err)}"}
    end
  end

  defp check_embedding(cfg) do
    case Delfos.LLM.Client.embed("test") do
      {:ok, vec} when is_list(vec) ->
        {:ok, "#{cfg[:provider]} OK · dim=#{length(vec)}"}

      {:error, reason} ->
        {:error, "#{cfg[:provider]}: #{format_probe_error(reason)}"}
    end
  end

  defp check_llm(%{provider: :local} = cfg) do
    case http_health(cfg[:url]) do
      {:ok, _} -> {:ok, "Server up · #{cfg[:url]}"}
      err -> {:warning, "Not available · summarize/explain will fail: #{format_probe_error(err)}"}
    end
  end

  defp check_llm(cfg) do
    case Delfos.LLM.Client.chat(
           [%{role: "user", content: "ping"}],
           max_tokens: 5,
           use_case: :summarize
         ) do
      {:ok, _} -> {:ok, "#{cfg[:provider]} API OK"}
      {:error, reason} -> {:error, "#{cfg[:provider]}: #{format_probe_error(reason)}"}
    end
  end

  defp http_health(url) when is_binary(url) do
    Req.get("#{url}/health", receive_timeout: 3_000)
  end

  defp http_health(_), do: {:error, :no_url}

  defp format_probe_error({:error, %Req.TransportError{reason: reason}}), do: inspect(reason)
  defp format_probe_error({:error, %{status: status}}), do: "HTTP #{status}"
  defp format_probe_error(other), do: inspect(other)

  # ---------------------------------------------------------------------------
  # Pretty output
  # ---------------------------------------------------------------------------

  defp print_results(results) do
    Enum.each(results, fn r ->
      msg = "#{r.name}: #{r.message}"

      case r.status do
        :ok -> Alaja.print_success(msg)
        :warning -> Alaja.print_warning(msg)
        :error -> Alaja.print_error(msg)
      end

      if r.status != :ok and r.fix_command do
        Alaja.print_info("  → #{r.fix_command}")
      end
    end)

    Alaja.print_raw("\n")
  end

  defp print_fix_report(%{applied: applied, failed: failed, skipped: skipped}) do
    if applied != [] do
      Alaja.print_raw("\nApplied fixes:\n")

      Enum.each(applied, fn id ->
        Alaja.print_success("  #{id}")
      end)
    end

    if failed != [] do
      Alaja.print_raw("\nFailed fixes:\n")

      Enum.each(failed, fn {id, reason} ->
        Alaja.print_error("  #{id}: #{reason}")
      end)
    end

    if skipped != [] do
      Alaja.print_raw("\nSkipped (no fix function or already OK):\n")

      Enum.each(skipped, fn id ->
        Alaja.print_info("  #{id}")
      end)
    end
  end

  defp print_summary(summary) do
    line =
      "#{summary.ok}/#{summary.total} ok · #{summary.warning} warnings · #{summary.error} errors"

    if summary.passed? do
      Alaja.print_success("PASSED — #{line}")
    else
      Alaja.print_error("FAILED — #{line}")
    end
  end

  # ---------------------------------------------------------------------------
  # Index health (separate from Botica checks; it's a DB query, not env check)
  # ---------------------------------------------------------------------------

  defp check_index_health do
    Alaja.print_raw("\n--- Index health ---\n\n")

    projects =
      Repo.all(
        from(p in Schema.Project,
          select: %{id: p.id, name: p.name, scanned: p.last_scanned}
        )
      )

    if Enum.empty?(projects) do
      Alaja.print_warning("No projects registered")
      Alaja.print_info("Next step: delfos init .")
    else
      Alaja.print_info("Projects: #{length(projects)}")

      Enum.each(projects, fn p ->
        total =
          Repo.one(from(s in Schema.Symbol, where: s.project_id == ^p.id, select: count())) || 0

        emb =
          Repo.one(
            from(s in Schema.Symbol,
              where: s.project_id == ^p.id and not is_nil(s.embedding),
              select: count()
            )
          ) || 0

        summ =
          Repo.one(
            from(s in Schema.Symbol,
              where: s.project_id == ^p.id and not is_nil(s.summary),
              select: count()
            )
          ) || 0

        cycles =
          Repo.one(
            from(m in Schema.FileMetrics,
              where: m.project_id == ^p.id and m.in_cycle == true,
              select: count()
            )
          ) || 0

        Alaja.print_info("  #{p.name} (last scan: #{p.scanned || "never"})")

        Alaja.print_raw(
          "    symbols=#{total} · embedded=#{pct(emb, total)}% · summarised=#{pct(summ, total)}%"
        )

        if cycles > 0 do
          Alaja.print_raw(" · cycles=#{cycles}")
        end

        Alaja.print_raw("\n")

        if emb < total do
          Alaja.print_info(
            "    #{total - emb} symbols missing embeddings · run: delfos scan --full"
          )
        end

        if summ == 0 and total > 0 do
          Alaja.print_info("    No LLM summaries yet · run: delfos summarize")
        end
      end)
    end

    Alaja.print_raw("\n")
  end

  defp pct(_, 0), do: 0
  defp pct(p, t), do: Float.round(p / t * 100, 1)
end
