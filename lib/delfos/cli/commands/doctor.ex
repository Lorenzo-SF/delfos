defmodule Delfos.CLI.Commands.Doctor do
  @moduledoc """
  Diagnóstico completo usando Apero.Doctor.
  Con --fix intenta resolver problemas detectados.
  """

  import Ecto.Query
  alias Delfos.{Repo, Schema}
  alias Delfos.Config.Manager

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [fix: :boolean])
    fix_mode = opts[:fix] || false

    IO.puts("\n=== DELFOS DOCTOR#{if fix_mode, do: " --fix", else: ""} ===\n")

    config = build_doctor_config()

    if fix_mode do
      Apero.Doctor.fix(config)
      IO.puts("\nPost-fix verification:\n")
    end

    {:ok, results} = Apero.Doctor.run(config)
    summary = Apero.Doctor.summary(results)

    Enum.each(results, fn r ->
      icon = case r.status do
        :ok -> "✓"; :warning -> "⚠"; :error -> "✗"
      end
      IO.puts("#{icon} #{r.name}: #{r.message}")
      if r.status != :ok and r.fix_command, do: IO.puts("  → #{r.fix_command}")
    end)

    IO.puts("")
    status = if summary.passed?, do: "PASSED", else: "FAILED"
    IO.puts("#{status} — #{summary.ok}/#{summary.total} ok, #{summary.warning} warnings, #{summary.error} errors")

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
            else: {:warning, "No existe. Ejecuta: delfos config init"}
          end,
          fix: fn -> Delfos.CLI.Commands.Config.run(["init"]); {:ok, "Creado"} end,
          fix_command: "delfos config init"},

        %{id: :postgresql, name: "PostgreSQL", description: "Conexión DB",
          priority: 2,
          check: fn ->
            case Repo.query("SELECT version()") do
              {:ok, %{rows: [[ver]]}} -> {:ok, String.slice(ver, 0, 50)}
              {:error, e} -> {:error, inspect(e)}
            end
          end,
          fix: fn -> :skipped end,
          fix_command: "Verifica DB_HOST, DB_USER, DB_PASS"},

        %{id: :pgvector, name: "pgvector", description: "Extensión vector",
          priority: 3,
          check: fn ->
            case Repo.query("SELECT extversion FROM pg_extension WHERE extname = 'vector'") do
              {:ok, %{rows: [[v]]}} -> {:ok, "v#{v}"}
              _ -> {:error, "No instalado"}
            end
          end,
          fix: fn ->
            case Repo.query("CREATE EXTENSION IF NOT EXISTS vector") do
              {:ok, _} -> {:ok, "Instalado"}; {:error, e} -> {:error, inspect(e)}
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
          description: "AST parser Rust",
          priority: 6,
          check: fn ->
            try do
              langs = Delfos.Parsers.TreeSitter.NIF.supported_languages()
              {:ok, "#{length(langs)} lenguajes con AST real"}
            rescue
              _ -> {:warning, "NIF no compilado. Usa: mix deps.compile"}
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
            if dim == cfg[:dim], do: {:ok, "dim=#{dim} ✓"},
            else: {:warning, "dim=#{dim} ≠ config=#{cfg[:dim]} — delfos config set embedding dim #{dim}"}
          {:error, r} -> {:warning, "Servidor activo, embed falló: #{inspect(r)}"}
        end
      _ -> {:error, "No disponible en #{cfg[:url]}"}
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
      {:ok, %{status: 200}} -> {:ok, "#{cfg[:url]} activo"}
      _ -> {:warning, "No disponible — summarize/explain no funcionarán"}
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
      IO.puts("\nNo hay proyectos — ejecuta: delfos init .")
    else
      IO.puts("\nProyectos:")
      Enum.each(projects, fn p ->
        total  = Repo.one(from s in Schema.Symbol, where: s.project_id == ^p.id, select: count()) || 0
        emb    = Repo.one(from s in Schema.Symbol, where: s.project_id == ^p.id and not is_nil(s.embedding), select: count()) || 0
        summ   = Repo.one(from s in Schema.Symbol, where: s.project_id == ^p.id and not is_nil(s.summary), select: count()) || 0
        cycles = Repo.one(from m in Schema.FileMetrics, where: m.project_id == ^p.id and m.in_cycle == true, select: count()) || 0

        IO.puts("  #{p.name} (#{p.scanned || "nunca"})")
        IO.puts("  Símbolos: #{total} | Embeddings: #{pct(emb, total)}% | Resúmenes: #{pct(summ, total)}%")
        if cycles > 0, do: IO.puts("  ⚠ #{cycles} archivos en ciclos")
        if emb < total, do: IO.puts("  ℹ #{total - emb} sin embedding → delfos scan --full")
        if summ == 0 and total > 0, do: IO.puts("  ℹ Sin resúmenes → delfos summarize")
      end)
    end
  end

  defp pct(_, 0), do: 0
  defp pct(p, t), do: Float.round(p / t * 100, 1)
end
