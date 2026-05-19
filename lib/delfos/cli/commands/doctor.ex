defmodule Delfos.CLI.Commands.Doctor do
  @moduledoc "Diagnóstico completo del índice y los servidores."

  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(_args) do
    IO.puts("\n=== DELFOS DOCTOR ===\n")

    check_db()
    check_pgvector()
    check_embedding_server()
    check_llm_server()
    check_index_health()

    IO.puts("")
  end

  # ---------------------------------------------------------------------------
  # Checks de infraestructura
  # ---------------------------------------------------------------------------

  defp check_db do
    case Repo.query("SELECT version()") do
      {:ok, %{rows: [[ver]]}} ->
        IO.puts("✓ PostgreSQL: #{String.slice(ver, 0, 40)}")

      {:error, e} ->
        IO.puts("✗ PostgreSQL: #{inspect(e)}")
    end
  rescue
    e -> IO.puts("✗ PostgreSQL: #{Exception.message(e)}")
  end

  defp check_pgvector do
    case Repo.query("SELECT extname, extversion FROM pg_extension WHERE extname = 'vector'") do
      {:ok, %{rows: [[_, ver]]}} ->
        IO.puts("✓ pgvector: v#{ver} instalado")

      _ ->
        IO.puts("✗ pgvector: NO instalado — ejecuta: CREATE EXTENSION vector;")
    end
  end

  defp check_embedding_server do
    cfg = Application.get_env(:delfos, :embedding)

    case Req.get("#{cfg[:url]}/health", receive_timeout: 3_000) do
      {:ok, %{status: 200}} ->
        # Verificar que el modelo responde y tiene la dimensión correcta
        case Delfos.LLM.Client.embed("test") do
          {:ok, vec} when is_list(vec) ->
            dim = length(vec)
            expected = cfg[:dim]

            if dim == expected do
              IO.puts("✓ Servidor embeddings: OK (#{cfg[:url]}, dim=#{dim})")
            else
              IO.puts(
                "⚠️  Servidor embeddings: activo pero dim=#{dim}, config espera dim=#{expected}"
              )

              IO.puts(
                "   Actualiza EMBED_DIM=#{dim} o cambia el modelo. Los vectores existentes serán incompatibles."
              )
            end

          {:error, reason} ->
            IO.puts("⚠️  Servidor embeddings: activo pero embed falló: #{inspect(reason)}")
        end

      _ ->
        IO.puts("✗ Servidor embeddings: NO disponible (#{cfg[:url]})")
        IO.puts("   Arráncalo con: MODEL_ID=embed PORT=9998 bash llm-server.sh")
    end
  end

  defp check_llm_server do
    cfg = Application.get_env(:delfos, :llm)

    case Req.get("#{cfg[:url]}/health", receive_timeout: 3_000) do
      {:ok, %{status: 200}} ->
        IO.puts("✓ LLM: disponible (#{cfg[:url]}, model=#{cfg[:model]})")

      _ ->
        IO.puts("! LLM: NO disponible — summarize y explain no funcionarán")
        IO.puts("   Arráncalo con: MODEL_ID=thinker bash llm-server.sh")
    end
  end

  # ---------------------------------------------------------------------------
  # Salud del índice
  # ---------------------------------------------------------------------------

  defp check_index_health do
    IO.puts("")

    projects = Repo.all(from(p in Schema.Project, select: %{id: p.id, name: p.name, scanned: p.last_scanned}))
    IO.puts("Proyectos indexados: #{length(projects)}")

    Enum.each(projects, fn p ->
      total_sym = Repo.one(from(s in Schema.Symbol, where: s.project_id == ^p.id, select: count(s.id))) || 0
      with_emb = Repo.one(from(s in Schema.Symbol, where: s.project_id == ^p.id and not is_nil(s.embedding), select: count(s.id))) || 0
      with_summary = Repo.one(from(s in Schema.Symbol, where: s.project_id == ^p.id and not is_nil(s.summary), select: count(s.id))) || 0
      total_chunks = Repo.one(from(c in Schema.Chunk, where: c.project_id == ^p.id, select: count(c.id))) || 0
      chunks_emb = Repo.one(from(c in Schema.Chunk, where: c.project_id == ^p.id and not is_nil(c.embedding), select: count(c.id))) || 0
      total_summaries = Repo.one(from(s in Schema.Summary, where: s.project_id == ^p.id, select: count(s.id))) || 0
      summaries_emb = Repo.one(from(s in Schema.Summary, where: s.project_id == ^p.id and not is_nil(s.embedding), select: count(s.id))) || 0
      cycles = Repo.one(from(m in Schema.FileMetrics, where: m.project_id == ^p.id and m.in_cycle == true, select: count(m.id))) || 0

      emb_pct = pct(with_emb, total_sym)
      sum_pct = pct(with_summary, total_sym)
      chunk_emb_pct = pct(chunks_emb, total_chunks)

      IO.puts("\n  Proyecto: #{p.name}")
      IO.puts("  Último scan:     #{p.scanned || "nunca"}")
      IO.puts("  Símbolos:        #{total_sym} (#{emb_pct}% con embedding, #{sum_pct}% con resumen)")
      IO.puts("  Chunks:          #{total_chunks} (#{chunk_emb_pct}% con embedding)")
      IO.puts("  Summaries:       #{total_summaries} (#{pct(summaries_emb, total_summaries)}% con embedding)")
      IO.puts("  Archivos en ciclo: #{cycles}")

      if with_emb < total_sym do
        IO.puts("  ⚠️  #{total_sym - with_emb} símbolos sin embedding — ejecuta: delfos scan --full")
      end

      if with_summary < total_sym do
        IO.puts("  ℹ️  #{total_sym - with_summary} símbolos sin resumen — ejecuta: delfos summarize")
      end

      if summaries_emb < total_summaries do
        IO.puts("  ⚠️  #{total_summaries - summaries_emb} summaries sin embedding — ejecuta: delfos summarize")
      end
    end)
  end

  defp pct(_part, 0), do: 0
  defp pct(part, total), do: Float.round(part / total * 100, 1)
end
