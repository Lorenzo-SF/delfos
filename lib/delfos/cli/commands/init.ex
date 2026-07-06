defmodule Delfos.CLI.Commands.Init do
  @moduledoc """
  Registers a project and runs the first full scan.

  Output is rendered through `Alaja` (icon-prefixed messages, raw
  sections where formatting isn't needed).
  """

  alias Alaja
  alias Delfos.{Repo, Schema}

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
      {:ok, _pid} -> :ok
      {:error, reason} ->
        Alaja.print_error("Database not available: #{reason}")
        Alaja.print_info("Run: delfos setup db")
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

    _project =
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

        existing ->
          Alaja.print_warning("Project already exists — updating metadata")

          Repo.update!(
            Schema.Project.changeset(existing, %{
              primary_stack: primary_stack,
              all_stacks: all_stacks,
              git_remote: git_info[:remote],
              git_branch: git_info[:branch],
              last_commit: git_info[:commit]
            })
          )
      end

    Alaja.print_raw("\n")
    Alaja.print_info("Starting full scan...")
    Delfos.CLI.Commands.Scan.run(["--full"])

    Alaja.print_success("#{name} indexed. Next steps:")

    Alaja.print_raw("""
      delfos summarize          # generate LLM summaries
      delfos integrate all --yes # configure AI agents
      delfos serve --mcp &      # start MCP server
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

  # 5s timeout for git reads during init — they're local, should be fast.
  @git_info_timeout 5_000

  defp read_git_info(path) do
    # Routed through Arrea.Command for consistent timeout + telemetry.
    # Each `git` invocation is wrapped in its own execute/2 call; a single
    # shell command (e.g. `git -C <path> remote get-url origin`) returns
    # {:ok, %{stdout: ..., exit_code: 0}} on success.
    git = fn args ->
      cmd = "git -C #{shell_escape(path)} #{Enum.join(args, " ")}"

      case Arrea.Command.execute(cmd, timeout: @git_info_timeout) do
        {:ok, %{exit_code: 0, stdout: out}} -> String.trim(out)
        _ -> nil
      end
    end

    %{
      remote: git.(["remote", "get-url", "origin"]),
      branch: git.(["rev-parse", "--abbrev-ref", "HEAD"]),
      commit: git.(["rev-parse", "--short", "HEAD"])
    }
  end

  # Escape spaces and shell metacharacters in a path so it's safe to
  # interpolate into a shell command. Wraps the value in single quotes.
  defp shell_escape(str) do
    "'" <> String.replace(str, "'", "'\\''") <> "'"
  end
end
