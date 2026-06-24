defmodule Delfos.CLI.Commands.Doctor do
  @moduledoc """
  Full diagnostic via `Apero.Doctor`.
  With `--fix` attempts to repair detected issues.

  Output is rendered through `Alaja` so check results and the index-health
  section get icon-prefixed messages.
  """

  import Ecto.Query
  alias Alaja
  alias Delfos.{Repo, Schema}
  alias Delfos.Config.Manager

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [fix: :boolean])
    fix_mode = opts[:fix] || false

    Alaja.print_raw("\n=== DELFOS DOCTOR#{if fix_mode, do: " --fix", else: ""} ===\n\n")

    config = build_doctor_config()

    if fix_mode do
      Apero.Doctor.fix(config)
      Alaja.print_raw("\nPost-fix verification:\n\n")
    end

    {:ok, results} = Apero.Doctor.run(config)
    summary = Apero.Doctor.summary(results)

    Enum.each(results, fn r ->
      alaja_fn =
        case r.status do
          :ok -> :print_success
          :warning -> :print_warning
          :error -> :print_error
        end

      apply(Alaja, alaja_fn, ["#{r.name}: #{r.message}"])

      if r.status != :ok and r.fix_command,
        do: Alaja.print_raw("  → #{r.fix_command}\n")
    end)

    Alaja.print_raw("\n")

    if summary.passed? do
      Alaja.print_success("PASSED — #{summary.ok}/#{summary.total} ok, #{summary.warning} warnings, #{summary.error} errors")
    else
      Alaja.print_error("FAILED — #{summary.ok}/#{summary.total} ok, #{summary.warning} warnings, #{summary.error} errors")
    end

    check_index_health()
  end

  defp build_doctor_config do
    cfg_emb = Manager.embedding()
    cfg_llm = Manager.llm()

    %{
      app_name: "delfos",
      checks: [
        %{id: :config_file, name: "Config file", description: Manager.config_file(),
          priority: 1,
          check: fn ->
            if File.exists?(Manager.config_file()), do: {:ok, Manager.config_file()},
            else: {:warning, "Not found. Run: delfos config init"}
          end,
          fix: fn -> Delfos.CLI.Commands.Config.run(["init"]); {:ok, "Created"} end,
          fix_command: "delfos config init"},

        %{id: :postgresql, name: "PostgreSQL", description: "DB connection",
          priority: 2,
          check: fn ->
            case Repo.query("SELECT version()") do
              {:ok, %{rows: [[ver]]}} -> {:ok, String.slice(ver, 0, 50)}
              {:error, e} -> {:error, inspect(e)}
            end
          end,
          fix: fn -> :skipped end,
          fix_command: "Check DB_HOST, DB_USER, DB_PASS"},

        %{id: :pgvector, name: "pgvector", description: "Vector extension",
          priority: 3,
          check: fn ->
            case Repo.query("SELECT extversion FROM pg_extension WHERE extname = 'vector'") do
              {:ok, %{rows: [[v]]}} -> {:ok, "v#{v}"}
              _ -> {:error, "Not installed"}
            end
          end,
          fix: fn ->
            case Repo.query("CREATE EXTENSION IF NOT EXISTS vector") do
              {:ok, _} -> {:ok, "Installed"}; {:error, e} -> {:error, inspect(e)}
            end
          end,
          fix_command: "psql -d delfos_dev -c 'CREATE EXTENSION vector;'"},

        %{id: :embedding, name: "Embedding (#{cfg_emb[:provider]})",
          description: "#{cfg_emb[:url]} #{cfg_emb[:model]}",
          priority: 4,
          check: fn -> check_embedding(cfg_emb) end,
          fix: fn -> :skipped end,
          fix_command: "llama-server -m bge-m3-q4_k_m.gguf --port 9998 --embedding --threads 4 --batch-size 64 --ctx-size 2048 --mlock --no-mmap --flash-attn --host 127.0.0.1"},

        %{id: :llm, name: "LLM (#{cfg_llm[:provider]})",
          description: "#{cfg_llm[:url]} #{cfg_llm[:model]}",
          priority: 5,
          check: fn -> check_llm(cfg_llm) end,
          fix: fn -> :skipped end,
          fix_command: "llama-server -m phi-4-mini-instruct-q4_k_m.gguf --port 8080 --threads 6 --batch-size 128 --ctx-size 8192 --mlock --no-mmap --flash-attn --host 127.0.0.1"},

        %{id: :tree_sitter, name: "Tree-sitter NIF",
          description: "Rust AST parser",
          priority: 6,
          check: fn ->
            try do
              langs = Delfos.Parsers.TreeSitter.NIF.supported_languages()
              {:ok, "#{length(langs)} languages with real AST"}
            rescue
              _ -> {:warning, "NIF not compiled. Run: mix deps.compile"}
            end
          end,
          fix: fn -> :skipped end,
          fix_command: "mix deps.compile tree_sitter_nif"}
      ]
    }
  end

  defp check_embedding(%{provider: :local} = cfg) do
    case Req.get("#{cfg[:url]}/health", receive_timeout: 3_000) do
      {:ok, %{status: 200}} ->
        case Delfos.LLM.Client.embed("test") do
          {:ok, vec} when is_list(vec) ->
            dim = length(vec)
            if dim == cfg[:dim], do: {:ok, "dim=#{dim}"},
            else: {:warning, "dim=#{dim} != config=#{cfg[:dim]} — delfos config set embedding dim #{dim}"}
          {:error, r} -> {:warning, "Server up, embed failed: #{inspect(r)}"}
        end
      _ -> {:error, "Not available at #{cfg[:url]}"}
    end
  end
  defp check_embedding(cfg) do
    case Delfos.LLM.Client.embed("test") do
      {:ok, v} when is_list(v) -> {:ok, "#{cfg[:provider]} OK dim=#{length(v)}"}
      {:error, r} -> {:error, "#{cfg[:provider]}: #{inspect(r)}"}
    end
  end

  defp check_llm(%{provider: :local} = cfg) do
    case Req.get("#{cfg[:url]}/health", receive_timeout: 3_000) do
      {:ok, %{status: 200}} -> {:ok, "#{cfg[:url]} up"}
      _ -> {:warning, "Not available — summarize/explain will not work"}
    end
  end
  defp check_llm(cfg) do
    case Delfos.LLM.Client.chat([%{role: "user", content: "ping"}],
           max_tokens: 5, use_case: :summarize) do
      {:ok, _} -> {:ok, "#{cfg[:provider]} API OK"}
      {:error, r} -> {:error, "#{cfg[:provider]}: #{inspect(r)}"}
    end
  end

  defp check_index_health do
    projects = Repo.all(from p in Schema.Project,
      select: %{id: p.id, name: p.name, scanned: p.last_scanned})

    if Enum.empty?(projects) do
      Alaja.print_raw("\n")
      Alaja.print_error("No projects — run: delfos init .")
    else
      Alaja.print_raw("\n")
      Alaja.print_info("Projects:")
      Enum.each(projects, fn p ->
        total  = Repo.one(from s in Schema.Symbol, where: s.project_id == ^p.id, select: count()) || 0
        emb    = Repo.one(from s in Schema.Symbol, where: s.project_id == ^p.id and not is_nil(s.embedding), select: count()) || 0
        summ   = Repo.one(from s in Schema.Symbol, where: s.project_id == ^p.id and not is_nil(s.summary), select: count()) || 0
        cycles = Repo.one(from m in Schema.FileMetrics, where: m.project_id == ^p.id and m.in_cycle == true, select: count()) || 0

        Alaja.print_raw("  #{p.name} (#{p.scanned || "never"})\n")
        Alaja.print_raw("  Symbols: #{total} | Embeddings: #{pct(emb, total)}% | Summaries: #{pct(summ, total)}%\n")
        if cycles > 0, do: Alaja.print_warning("#{cycles} files in cycles")
        if emb < total, do: Alaja.print_info("#{total - emb} missing embeddings — run: delfos scan --full")
        if summ == 0 and total > 0, do: Alaja.print_info("No summaries yet — run: delfos summarize")
      end)
    end
  end

  defp pct(_, 0), do: 0
  defp pct(p, t), do: Float.round(p / t * 100, 1)
end
