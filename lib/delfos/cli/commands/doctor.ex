defmodule Delfos.CLI.Commands.Doctor do
  import Ecto.Query
  alias Delfos.{Repo, Schema}

  def run(_args) do
    IO.puts("\n=== DELFOS DOCTOR ===\n")

    # DB
    case Repo.query("SELECT 1") do
      {:ok, _} -> IO.puts("✓ PostgreSQL: conectado")
      {:error, e} -> IO.puts("✗ PostgreSQL: #{inspect(e)}")
    end

    # pgvector
    case Repo.query("SELECT extname FROM pg_extension WHERE extname = 'vector'") do
      {:ok, %{rows: [[_]]}} -> IO.puts("✓ pgvector: instalado")
      _ -> IO.puts("✗ pgvector: NO instalado — ejecuta: CREATE EXTENSION vector;")
    end

    # Proyectos
    count = Repo.one(from(p in Schema.Project, select: count(p.id)))
    IO.puts("✓ Proyectos indexados: #{count}")

    # Embeddings
    with_emb =
      Repo.one(from(s in Schema.Symbol, where: not is_nil(s.embedding), select: count(s.id)))

    total = Repo.one(from(s in Schema.Symbol, select: count(s.id)))
    IO.puts("✓ Símbolos con embedding: #{with_emb}/#{total}")

    # Servidor de embeddings
    cfg = Application.get_env(:delfos, :embedding)

    case Req.get("#{cfg[:url]}/health", receive_timeout: 3_000) do
      {:ok, %{status: 200}} ->
        IO.puts("✓ Servidor de embeddings: disponible (#{cfg[:url]})")

      _ ->
        IO.puts("! Servidor de embeddings: NO disponible — embeddings usarán fallback o fallarán")
    end

    # LLM
    llm_cfg = Application.get_env(:delfos, :llm)

    case Req.get("#{llm_cfg[:url]}/health", receive_timeout: 3_000) do
      {:ok, %{status: 200}} -> IO.puts("✓ LLM: disponible (#{llm_cfg[:url]})")
      _ -> IO.puts("! LLM: NO disponible — summarize y explain no funcionarán")
    end

    IO.puts("")
  end
end
