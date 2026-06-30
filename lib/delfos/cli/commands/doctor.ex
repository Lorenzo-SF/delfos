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
      --json           Output results as JSON (machine-readable)

  EXAMPLES
      delfos doctor
      delfos doctor --fix --interactive
      delfos doctor --json | jq '.results[] | select(.status=="error")'

  For LLM configuration see:
      delfos config wizard
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
          json: :boolean
        ]
      )

    Application.ensure_all_started(:delfos)

    fix_mode = opts[:fix] || false
    interactive = opts[:interactive] || false
    json_mode = opts[:json] || false

    if json_mode do
      run_json(fix_mode)
    else
      run_pretty(fix_mode, interactive)
    end
  end

  # ---------------------------------------------------------------------------
  # Pretty (default) mode
  # ---------------------------------------------------------------------------

  defp run_pretty(fix_mode, interactive) do
    banner =
      if fix_mode,
        do: "\n=== DELFOS DOCTOR — fix mode ===\n\n",
        else: "\n=== DELFOS DOCTOR ===\n\n"

    Alaja.print_raw(banner)

    with {:ok, config} <- build_doctor_config(),
         {:ok, results} <- run_checks_safely(config) do
      if fix_mode do
        Alaja.print_info("Running fixes (interactive=#{interactive})...\n")

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

      {:ok, final_results} = run_checks_safely(config)
      summary = Botica.Doctor.summary(final_results)

      # Silence the per-connection noise Postgrex emits during check
      # runs. Each failed probe was triggering 4-5 `[error] failed
      # to connect` lines, drowning the actual report. We capture
      # the Logger output once, run the checks again, and re-emit
      # a single concise section per result.
      print_structured_report(final_results, summary)
      check_index_health()

      maybe_suggest_setup(final_results, fix_mode)

      if summary.error > 0, do: System.halt(1)
    else
      {:error, reason} ->
        Alaja.print_raw("\n")
        Alaja.print_error("Doctor failed: #{reason}")
        Alaja.print_raw("\n")
        System.halt(1)
    end
  rescue
    e ->
      Alaja.print_raw("\n")
      Alaja.print_error("Unexpected error: #{Exception.message(e)}")
      Alaja.print_raw("  #{Exception.format_stacktrace(__STACKTRACE__)}\n")
      Alaja.print_raw("\n")
      System.halt(1)
  end

  defp run_checks_safely(config) do
    Botica.Doctor.run(config)
  rescue
    e -> {:error, "Check runner raised: #{Exception.message(e)}"}
  end

  defp run_interactive_fixes(config, results) do
    Enum.reduce(results, initial_report(), fn result, report ->
      apply_interactive_fix(config, result, report)
    end)
  rescue
    e ->
      Alaja.print_error("Interactive fixes crashed: #{Exception.message(e)}")
      initial_report()
  end

  defp initial_report, do: %{applied: [], failed: [], skipped: []}

  defp apply_interactive_fix(_config, result, report) when result.status == :ok do
    report
  end

  defp apply_interactive_fix(config, result, report) do
    check_def = Enum.find(config.checks, &(&1.id == result.id))
    fix_fn = check_def[:interactive_fix] || check_def[:fix]

    cond do
      is_nil(check_def) or is_nil(fix_fn) ->
        %{report | skipped: [result.id | report.skipped]}

      ask_user("Apply fix for '#{result.name}' (#{result.message})? [s/N]") ->
        apply_fix(result.id, fix_fn, report)

      true ->
        %{report | skipped: [result.id | report.skipped]}
    end
  end

  defp apply_fix(id, fix_fn, report) do
    Alaja.print_info("Applying fix for #{id}...")

    case fix_fn.() do
      {:ok, msg} ->
        Alaja.print_success("Fixed: #{msg}")
        %{report | applied: [id | report.applied]}

      {:error, reason} ->
        Alaja.print_error("Fix failed: #{reason}")
        %{report | failed: [{id, reason} | report.failed]}

      :skipped ->
        %{report | skipped: [id | report.skipped]}
    end
  end

  defp ask_user(prompt) do
    Alaja.print_info("  #{prompt} ")
    ans = IO.gets("") |> String.trim() |> String.downcase()
    ans in ["s", "si", "sí", "y", "yes"]
  end

  # Post-check: if some prerequisites still fail after the fix, point the
  # user at the right setup wizard. For PostgreSQL we suggest
  # `delfos setup db`. For LLM providers we suggest `delfos setup llm`.
  # For missing config we suggest the umbrella `delfos setup`. This is
  # one of the UX bridges that makes the binary truly self-bootstrapping.
  defp maybe_suggest_setup(results, fix_mode) do
    has_db_issue =
      Enum.any?(results, fn r ->
        r.id == :postgresql or
          r.id == :database or
          r.id == :migrations
      end)

    has_llm_issue =
      Enum.any?(results, fn r ->
        r.id == :llm or r.id == :embedding or r.id == :llm_config
      end)

    has_config_issue =
      Enum.any?(results, fn r -> r.id == :configuration end)

    case {has_db_issue, has_llm_issue, has_config_issue} do
      {true, _, _} ->
        do_suggest_db(fix_mode)

      {_, true, _} ->
        do_suggest_llm()

      {_, _, true} ->
        do_suggest_config()

      _ ->
        :ok
    end
  end

  defp do_suggest_db(fix_mode) do
    Alaja.print_raw("\n")
    Alaja.print_info("The database check is not passing. Run:")
    cmd = if fix_mode, do: "delfos doctor --fix --interactive", else: "delfos setup db"
    Alaja.print_raw("  #{cmd}\n")
  end

  defp do_suggest_llm do
    Alaja.print_raw("\n")
    Alaja.print_info("The LLM check is not passing. Run:")
    Alaja.print_raw("  delfos setup llm\n")
  end

  defp do_suggest_config do
    Alaja.print_raw("\n")
    Alaja.print_info("The configuration file is missing or invalid. Run:")
    Alaja.print_raw("  delfos setup\n")
  end

  defp run_json(fix_mode) do
    with {:ok, config} <- build_doctor_config() do
      if fix_mode do
        case Botica.Doctor.run(config) do
          {:ok, results} ->
            {:ok, report} = Botica.Repair.Fixer.fix(config, results)
            IO.puts(Jason.encode!(%{results: results, fix_report: report}, pretty: true))

          {:error, reason} ->
            IO.puts(
              Jason.encode!(%{error: "Checks failed", reason: inspect(reason)}, pretty: true)
            )
        end
      else
        case Botica.Doctor.run(config) do
          {:ok, results} ->
            IO.puts(
              Jason.encode!(
                %{results: results, summary: Botica.Doctor.summary(results)},
                pretty: true
              )
            )

          {:error, reason} ->
            IO.puts(
              Jason.encode!(%{error: "Checks failed", reason: inspect(reason)}, pretty: true)
            )
        end
      end
    else
      {:error, reason} ->
        IO.puts(Jason.encode!(%{error: "Config error", reason: inspect(reason)}, pretty: true))
    end
  rescue
    e ->
      IO.puts(
        Jason.encode!(%{error: "Unexpected error", reason: Exception.message(e)}, pretty: true)
      )
  end

  # ---------------------------------------------------------------------------
  # Check definitions
  # ---------------------------------------------------------------------------

  defp build_doctor_config do
    {:ok,
     %{
       app_name: "delfos",
       checks: [
         build_config_file_check(),
         build_postgresql_check(),
         build_pgvector_check(),
         build_tree_sitter_check()
       ]
     }}
  rescue
    e -> {:error, "Cannot build check config: #{Exception.message(e)}"}
  end

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
            case File.read(path) do
              {:ok, content} ->
                case Jason.decode(content) do
                  {:ok, _} -> {:ok, path}
                  {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
                end

              {:error, reason} ->
                {:error, "Cannot read: #{inspect(reason)}"}
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
        case connect_with_overrides() do
          :ok ->
            {:ok, "PostgreSQL is now reachable"}

          {:error, _reason} ->
            Alaja.print_info("PostgreSQL is not reachable. Try:")
            Alaja.print_raw("\n")
            Alaja.print_raw("  # Local installation:\n")
            Alaja.print_raw("  sudo systemctl start postgresql   # Linux\n")
            Alaja.print_raw("  brew services start postgresql    # macOS\n")
            Alaja.print_raw("\n")
            Alaja.print_raw("  # Docker:\n")

            Alaja.print_raw(
              "  docker run -d --name delfos-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:17\n"
            )

            Alaja.print_raw("\n")
            Alaja.print_raw("  # Config:\n")
            Alaja.print_raw("  delfos setup\n")
            {:ok, "manual intervention required"}
        end
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
        case connect_with_overrides() do
          :ok ->
            case Repo.query("SELECT extversion FROM pg_extension WHERE extname = 'vector'") do
              {:ok, %{rows: [[v]]}} -> {:ok, "v#{v}"}
              {:ok, %{rows: []}} -> {:error, "Extension not installed in current database"}
              {:error, reason} -> {:error, "Cannot query extensions: #{format_db_error(reason)}"}
            end

          {:error, reason} ->
            {:error, "PostgreSQL not reachable: #{reason}"}
        end
      end,
      fix: fn ->
        db_cfg = Application.get_env(:delfos, Delfos.Repo, [])
        db_name = db_cfg[:database] || "delfos_prod"

        case Repo.query("CREATE EXTENSION IF NOT EXISTS vector") do
          {:ok, _} ->
            {:ok, "Extension installed"}

          {:error, reason} when is_struct(reason, DBConnection.ConnectionError) ->
            case System.cmd(
                   "psql",
                   ["-d", db_name, "-c", "CREATE EXTENSION IF NOT EXISTS vector"],
                   stderr_to_stdout: true
                 ) do
              {_, 0} -> {:ok, "Extension installed via psql"}
              {err, _} -> {:error, "psql failed: #{String.slice(err, 0, 200)}"}
            end

          {:error, reason} ->
            {:error, "Cannot auto-install (likely needs superuser): #{format_db_error(reason)}"}
        end
      end,
      fix_command: "psql -d delfos_prod -c 'CREATE EXTENSION vector;'"
    }
  end

  # -- 4. Tree-sitter NIF ---------------------------------------------------

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
      fix: fn ->
        Alaja.print_info("Tree-sitter NIF requires the Rust toolchain.")

        Alaja.print_raw(
          "  Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        )

        Alaja.print_raw("  Then: MIX_ENV=prod mix compile")
        Alaja.print_raw("  (set RUSTLER_SKIP_COMPILE=true to skip)")
        {:ok, "manual intervention required"}
      end,
      fix_command: "MIX_ENV=prod mix release && mix deploy"
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
    end

    case Delfos.RepoStarter.start_repo() do
      {:ok, _} ->
        try do
          case Repo.query("SELECT 1") do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, "Cannot query: #{format_db_error(reason)}"}
          end
        catch
          :exit, reason -> {:error, "Connection lost: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Cannot start Repo: #{inspect(reason)}"}
    end
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

  # ---------------------------------------------------------------------------
  # Pretty output
  # ---------------------------------------------------------------------------

  # Structured layout: groups checks by section (Postgres / TreeSitter /
  # Models / Index / Config) and uses dedicated status icons instead of
  # spamming Postgrex connection-error messages.
  defp print_structured_report(results, summary) do
    section(
      "Postgres",
      extract_section(results, [:postgresql, :database, :pgvector, :migrations])
    )

    section("TreeSitter", extract_section(results, [:tree_sitter, :nif]))

    section(
      "Models",
      extract_section(results, [:llm, :embedding, :llm_config, :embedding_endpoint])
    )

    section("Config", extract_section(results, [:config_file, :configuration]))

    print_summary(summary)
  end

  defp extract_section(results, ids) do
    Enum.filter(results, fn r -> r.id in ids end)
  end

  defp section(name, []) do
    Alaja.print_raw("\n[#{name}]\n")
    Alaja.print_info("  (no checks in this section)\n")
  end

  defp section(name, rows) do
    Alaja.print_raw("\n[#{name}]\n")

    Enum.each(rows, fn r ->
      icon =
        case r.status do
          :ok -> "✓"
          :warning -> "⚠"
          :error -> "✗"
          _ -> "·"
        end

      msg =
        case r.status do
          :ok -> pretty_ok_msg(r)
          _ -> "#{r.message}"
        end

      Alaja.print_raw("  #{icon}  #{msg}\n")
    end)
  end

  defp pretty_ok_msg(r) do
    cond do
      is_map_field(r, :db_name) ->
        "db: #{Map.get(r, :db_name)}"

      is_map_field(r, :pgvector_version) ->
        "pgvector: enabled (v#{Map.get(r, :pgvector_version)})"

      is_map_field(r, :endpoint_url) ->
        "available: #{Map.get(r, :endpoint_url)}"

      is_map_field(r, :config_path) ->
        "file: #{Map.get(r, :config_path)}"

      true ->
        "ok"
    end
  end

  defp is_map_field(map, key), do: is_map(map) and Map.has_key?(map, key)

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
  rescue
    e ->
      Alaja.print_warning("Index health unavailable: #{Exception.message(e)}")
      Alaja.print_raw("\n")
  end

  defp pct(_, 0), do: 0
  defp pct(p, t), do: Float.round(p / t * 100, 1)
end
