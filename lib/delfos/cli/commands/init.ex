defmodule Delfos.CLI.Commands.Init do
  @moduledoc """
  Registers a project and runs the first full scan.

  Output is rendered through `Alaja` (icon-prefixed messages, raw
  sections where formatting isn't needed).
  """

  alias Alaja
  alias Delfos.{Repo, Schema}
  alias Trebejo.Util

  @help """
  USAGE
      delfos init [path]

  Register a project and run the first full scan.

  ARGUMENTS
      path           Directory to index (default: current directory)

  EXAMPLES
      delfos init .
      delfos init ~/code/my-app

  After init you'll see the recommended next steps.
  """

  def run(["--help"]) do
    Alaja.print_raw(@help)
  end

  def run(["-h"]) do
    Alaja.print_raw(@help)
  end

  def run(args) do
    # Ensure OTP app is running (starts RepoStarter, Ecto repo, etc.)
    Application.ensure_all_started(:delfos)

    case Delfos.RepoStarter.start_repo() do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Alaja.print_error("Database not available: #{reason}")
        Alaja.print_info("Run: delfos config setup db")
        System.halt(1)
    end

    path = List.first(args) || File.cwd!()
    path = Path.expand(path)

    unless File.dir?(path) do
      Alaja.print_error("Path does not exist or is not a directory: #{path}")
      System.halt(1)
    end

    name = Path.basename(path)
    primary_stack = detect_primary_stack(path)
    all_stacks = detect_all_stacks(path)
    git_info = read_git_info(path)

    Alaja.print_info("Initializing: #{name}")
    Alaja.print_raw("  Stack: #{primary_stack} | Stacks: #{Enum.join(all_stacks, ", ")}\n")
    Alaja.print_raw("  Git: #{git_info[:branch] || "—"} @ #{git_info[:commit] || "—"}\n")

    # Bug fix: LLMDiscovery debe correr ANTES del scan (no después)
    # porque el scan necesita los LLMs para generar embeddings de los
    # chunks. Antes, si los LLMs estaban caídos, el scan fallaba con
    # 'embedding unavailable' para cada chunk. Ahora arrancamos los
    # LLMs automáticamente (en modo no-interactivo) o preguntamos al
    # usuario antes de empezar a indexar.
    Delfos.Config.LLMDiscovery.ensure_running(yes: true)

    # Decide project action. If new, insert and proceed to scan.
    # If existing, ask user (Keep / Wipe / Cancel) and respect choice.
    # Bug #19 fix: antes, después de handle_existing_project el código
    # SIEMPRE hacía Scan.run_with_opts(%{full: true}), contradiciendo
    # el mensaje 'Keeping existing data; updating metadata...'. Ahora
    # la acción retornada (que es :new/:keep/:wipe/:cancel) determina
    # si se hace un full re-scan.
    action =
      case Repo.get_by(Schema.Project, path: path) do
        nil ->
          Repo.insert!(
            Schema.Project.changeset(%Schema.Project{}, %{
              name: name,
              path: path,
              primary_stack: primary_stack,
              all_stacks: all_stacks,
              git_remote: git_info[:remote],
              git_branch: git_info[:branch],
              last_commit: git_info[:commit]
            })
          )

          :new

        %Schema.Project{} = existing ->
          handle_existing_project(existing, path, primary_stack, all_stacks, git_info)
      end

    case action do
      :new ->
        Alaja.print_raw("\n")
        Alaja.print_info("Starting full scan...")
        Delfos.CLI.Commands.Scan.run_with_opts(%{full: true})

      :keep ->
        # Refresh last_scanned para que el dashboard refleje la
        # decisión del usuario. No re-indexamos los archivos.
        Alaja.print_info("Skipping scan (use 'delfos scan --full' to re-index).")

      :wipe ->
        Alaja.print_raw("\n")
        Alaja.print_info("Starting full scan...")
        Delfos.CLI.Commands.Scan.run_with_opts(%{full: true})

      :cancel ->
        System.halt(0)
    end

    Alaja.print_raw("\n")
    Alaja.print_info("Checking local LLM services...")
    Delfos.Config.LLMDiscovery.ensure_running()

    Alaja.print_success("#{name} indexed. Next steps:")

    Alaja.print_raw("""

      delfos summarize          # generate LLM summaries
      delfos integrate all --yes # configure AI agents
      delfos mcp &               # start MCP server
      delfos query "..."        # search the index
    """)
  end

  @doc false
  def detect_primary_stack(path) do
    cond do
      File.exists?("#{path}/mix.exs") -> "elixir"
      File.exists?("#{path}/Cargo.toml") -> "rust"
      File.exists?("#{path}/go.mod") -> "go"
      File.exists?("#{path}/pyproject.toml") or File.exists?("#{path}/setup.py") -> "python"
      File.exists?("#{path}/package.json") -> "node"
      File.exists?("#{path}/pom.xml") or File.exists?("#{path}/build.gradle") -> "java"
      File.exists?("#{path}/pubspec.yaml") -> "dart"
      File.exists?("#{path}/Gemfile") -> "ruby"
      File.exists?("#{path}/composer.json") -> "php"
      true -> "unknown"
    end
  end

  defp handle_existing_project(existing, _path, primary_stack, all_stacks, git_info) do
    Alaja.print_warning("Project already exists in the index (id=#{existing.id}).")
    Alaja.print_raw("\n")
    Alaja.print_info("Current state:")
    Alaja.print_raw("  Path:        #{existing.path}\n")
    Alaja.print_raw("  Stack:       #{existing.primary_stack}\n")
    Alaja.print_raw("  Last scan:   #{existing.last_scanned || "never"}\n")
    Alaja.print_raw("\n")

    case Alaja.Printer.Interactive.question_with_options(
           "Project is already indexed. What do you want to do?",
           [
             {"Keep existing data, just refresh metadata", :keep},
             {"Wipe and re-index from scratch (delete all symbols/files)", :wipe},
             {"Cancel init", :cancel}
           ]
         ) do
      :keep ->
        Alaja.print_info("Keeping existing data; updating metadata...")

        Repo.update!(
          Schema.Project.changeset(existing, %{
            primary_stack: primary_stack,
            all_stacks: all_stacks,
            git_remote: git_info[:remote],
            git_branch: git_info[:branch],
            last_commit: git_info[:commit]
          })
        )

        :keep

      :wipe ->
        Alaja.print_info("Wiping existing data...")
        wipe_project(existing.id)

        Repo.update!(
          Schema.Project.changeset(existing, %{
            primary_stack: primary_stack,
            all_stacks: all_stacks,
            git_remote: git_info[:remote],
            git_branch: git_info[:branch],
            last_commit: git_info[:commit]
          })
        )

        :wipe

      :cancel ->
        Alaja.print_warning("Init cancelled.")
        :cancel

      :error ->
        # Non-interactive context (no TTY). Default to keeping existing data.
        Alaja.print_warning("Non-interactive mode: keeping existing data; updating metadata.")

        Repo.update!(
          Schema.Project.changeset(existing, %{
            primary_stack: primary_stack,
            all_stacks: all_stacks,
            git_remote: git_info[:remote],
            git_branch: git_info[:branch],
            last_commit: git_info[:commit]
          })
        )

        :keep
    end
  end

  defp wipe_project(project_id) do
    # Delete in dependency order. Children first, then parents.
    import Ecto.Query

    Repo.delete_all(from(s in Delfos.Schema.Symbol, where: s.project_id == ^project_id))
    Repo.delete_all(from(c in Delfos.Schema.Chunk, where: c.project_id == ^project_id))
    Repo.delete_all(from(s in Delfos.Schema.Summary, where: s.project_id == ^project_id))
    Repo.delete_all(from(r in Delfos.Schema.Relationship, where: r.project_id == ^project_id))
    Repo.delete_all(from(m in Delfos.Schema.FileMetrics, where: m.project_id == ^project_id))
    Repo.delete_all(from(f in Delfos.Schema.File, where: f.project_id == ^project_id))
    Alaja.print_success("All indexed data wiped.")
  end

  @doc false
  def detect_all_stacks(path) do
    [
      {"elixir", "mix.exs"},
      {"rust", "Cargo.toml"},
      {"go", "go.mod"},
      {"python", "pyproject.toml"},
      {"node", "package.json"},
      {"java", "pom.xml"},
      {"dart", "pubspec.yaml"},
      {"ruby", "Gemfile"},
      {"php", "composer.json"}
    ]
    |> Enum.filter(fn {_, f} -> File.exists?("#{path}/#{f}") end)
    |> Enum.map(fn {s, _} -> s end)
    |> case do
      [] -> ["unknown"]
      s -> s
    end
  end

  defp read_git_info(path) do
    git = fn args -> run_git(path, args) end

    %{
      remote: git.(["remote", "get-url", "origin"]),
      branch: git.(["rev-parse", "--abbrev-ref", "HEAD"]),
      commit: git.(["rev-parse", "--short", "HEAD"])
    }
  end

  defp run_git(path, args) do
    case Util.run_cmd_legacy("git", ["-C", path] ++ args, timeout: 5_000) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end
end
