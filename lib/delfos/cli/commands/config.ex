defmodule Delfos.CLI.Commands.Config do
  @moduledoc """
  Gestión de la configuración global de Delfos.

  Fichero: ~/.config/delfos/delfos.conf

  Subcomandos:
    show                       Muestra la configuración activa
    get <sección> <clave>      Lee un valor
    set <sección> <clave> <v>  Escribe un valor
    init                       Crea el fichero con valores por defecto
    preset <nombre>            Aplica un preset de proveedor predefinido
    path                       Muestra la ruta del fichero de config
  """

  alias Delfos.Config.Manager

  # Presets de proveedores más usados
  @presets %{
    "local" => [
      {"embedding", "provider", "local"},
      {"embedding", "url", "http://127.0.0.1:9998"},
      {"embedding", "model", "mxbai-embed-v1"},
      {"embedding", "api_key", "sk-local-dev"},
      {"embedding", "dim", "1024"},
      {"llm", "provider", "local"},
      {"llm", "url", "http://127.0.0.1:8080"},
      {"llm", "model", "thinker"},
      {"llm", "api_key", "sk-local-dev"}
    ],
    "anthropic" => [
      {"llm", "provider", "anthropic"},
      {"llm", "url", "https://api.anthropic.com"},
      {"llm", "model", "claude-sonnet-4-20250514"}
    ],
    "openai" => [
      {"embedding", "provider", "openai"},
      {"embedding", "url", "https://api.openai.com"},
      {"embedding", "model", "text-embedding-3-small"},
      {"embedding", "dim", "1536"},
      {"llm", "provider", "openai"},
      {"llm", "url", "https://api.openai.com"},
      {"llm", "model", "gpt-4o-mini"}
    ],
    "openai-large" => [
      {"embedding", "provider", "openai"},
      {"embedding", "url", "https://api.openai.com"},
      {"embedding", "model", "text-embedding-3-large"},
      {"embedding", "dim", "3072"},
      {"llm", "provider", "openai"},
      {"llm", "url", "https://api.openai.com"},
      {"llm", "model", "gpt-4o"}
    ]
  }

  def run(["show" | _]) do
    IO.puts(Manager.show())
  end

  def run(["path" | _]) do
    IO.puts(Manager.config_file())
  end

  def run(["init" | _]) do
    path = Manager.config_file()

    if File.exists?(path) do
      IO.puts("Ya existe: #{path}")
      IO.puts("Usa 'delfos config show' para ver la configuración actual.")
    else
      # ensure_config_exists se llama en load(), forzamos creando el fichero
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, default_config_content())
      IO.puts("Creado: #{path}")
    end
  end

  def run(["get", section, key | _]) do
    cfg = Manager.load()

    case get_in(cfg, [section, key]) do
      nil -> IO.puts("(no encontrado: [#{section}] #{key})")
      value -> IO.puts(to_string(value))
    end
  end

  def run(["set", section, key, value | _]) do
    case Manager.set(section, key, value) do
      :ok ->
        IO.puts("✓ [#{section}] #{key} = #{value}")

        # Advertir si se cambia el proveedor de embeddings y hay dim desalineada
        if section == "embedding" and key == "provider" do
          suggest_dim_for_provider(value)
        end

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  def run(["preset", name | _]) do
    case Map.get(@presets, name) do
      nil ->
        IO.puts("Preset desconocido: #{name}")
        IO.puts("Presets disponibles: #{Map.keys(@presets) |> Enum.join(", ")}")

      changes ->
        IO.puts("Aplicando preset '#{name}'...")

        Enum.each(changes, fn {section, key, value} ->
          Manager.set(section, key, value)
          IO.puts("  [#{section}] #{key} = #{value}")
        end)

        IO.puts("\n✓ Preset '#{name}' aplicado.")

        cond do
          name == "anthropic" ->
            IO.puts("\nRecuerda configurar tu API key:")
            IO.puts("  delfos config set llm api_key sk-ant-TU_API_KEY")

            IO.puts(
              "\nNota: Anthropic no soporta embeddings. El embedding usará el proveedor que tengas configurado."
            )

          name in ["openai", "openai-large"] ->
            IO.puts("\nRecuerda configurar tu API key:")
            IO.puts("  delfos config set llm api_key sk-TU_API_KEY")
            IO.puts("  delfos config set embedding api_key sk-TU_API_KEY")
            IO.puts("\n⚠️  Si cambias dim, recrea la DB: mix ecto.reset && delfos init")

          true ->
            IO.puts("\nAsegúrate de tener los servidores locales arrancados:")
            IO.puts("  MODEL_ID=thinker bash llm-server.sh")
            IO.puts("  MODEL_ID=embed PORT=9998 bash llm-server.sh")
        end
    end
  end

  def run(["preset" | _]) do
    IO.puts("Presets disponibles:\n")

    Enum.each(@presets, fn {name, changes} ->
      IO.puts("  #{name}")
      Enum.each(changes, fn {s, k, v} -> IO.puts("    [#{s}] #{k} = #{v}") end)
      IO.puts("")
    end)
  end

  def run(_) do
    IO.puts("""
    Uso: delfos config <subcomando>

    Subcomandos:
      show                         Muestra configuración activa
      path                         Ruta del fichero de config
      init                         Crea fichero con valores por defecto
      get <sección> <clave>        Lee un valor
      set <sección> <clave> <val>  Escribe un valor
      preset <nombre>              Aplica preset de proveedor

    Secciones: embedding | llm | analysis | indexing

    Presets: #{Map.keys(@presets) |> Enum.join(" | ")}

    Ejemplos:
      delfos config show
      delfos config set llm provider anthropic
      delfos config set llm api_key sk-ant-xxxxx
      delfos config preset openai
      delfos config set embedding api_key sk-xxxxx
      delfos config get llm model
    """)
  end

  # ---------------------------------------------------------------------------
  # Privado
  # ---------------------------------------------------------------------------

  defp suggest_dim_for_provider("openai") do
    IO.puts(
      "\n  ℹ️  Para text-embedding-3-small usa dim=1536, para text-embedding-3-large usa dim=3072"
    )

    IO.puts("  Aplica con: delfos config preset openai  (o openai-large)")
  end

  defp suggest_dim_for_provider("local") do
    IO.puts("\n  ℹ️  Para mxbai-embed-large usa dim=1024, para nomic-embed usa dim=768")
  end

  defp suggest_dim_for_provider(_), do: :ok

  defp default_config_content do
    # Lee del Manager para que sea consistente
    File.read!(Path.join(:code.priv_dir(:delfos), "delfos.conf.default"))
  rescue
    _ ->
      # Fallback si no hay fichero en priv/
      """
      [embedding]
      provider = "local"
      url      = "http://127.0.0.1:9998"
      model    = "mxbai-embed-v1"
      api_key  = "sk-local-dev"
      dim      = 1024
      batch_size = 32
      timeout_ms = 30000

      [llm]
      provider  = "local"
      url       = "http://127.0.0.1:8080"
      model     = "thinker"
      api_key   = "sk-local-dev"
      timeout_ms = 60000
      max_tokens = 2048

      [analysis]
      churn_max_commits = 1000
      """
  end
end
