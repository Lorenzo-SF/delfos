defmodule Delfos.Indexer.Sandbox do
  @moduledoc """
  Validates that a project path is safe to index.

  SE-1 (S5): the scanner previously accepted any path, including
  sensitive directories like ~/.ssh, ~/.aws, ~/.kube, /etc, /var,
  /proc, /sys. A malicious project config or accidental `delfos init
  ~/.ssh` could exfiltrate private keys, AWS credentials, etc.

  This module enforces:
    1. Deny-list (always reject, even with --force)
    2. Allow-list heuristics (require a project marker; --force
       bypasses this)
    3. Path validation (must be absolute, must exist, must be a dir)
  """
  @project_markers ~w(mix.exs package.json pyproject.toml Cargo.toml go.mod pom.xml build.gradle project.clj rebar3.config)

  # Directories that must NEVER be indexed. --force does not bypass.
  @forbidden_prefixes [
    "/etc",
    "/var",
    "/proc",
    "/sys",
    Path.expand("~/.ssh"),
    Path.expand("~/.aws"),
    Path.expand("~/.kube"),
    Path.expand("~/.gnupg"),
    Path.expand("~/.config/gh")
  ]

  # Directories allowed with --force but blocked by default.
  @sensitive_prefixes [
    Path.expand("~"),
    "/home",
    "/root",
    "/Users"
  ]

  @doc """
  Validates a project path. Returns :ok if safe, {:error, reason} otherwise.

  Options:
    * `:force` — bypass the allow-list heuristic (still respects deny-list).
                 For example, indexing your home dir with --force is OK;
                 without --force, it requires a project marker.
  """
  @spec validate(Path.t(), keyword()) :: :ok | {:error, String.t()}
  def validate(path, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    cond do
      not is_binary(path) or path == "" ->
        {:error, "Invalid path: must be a non-empty string"}

      true ->
        real_path =
          path
          |> Path.absname()
          |> String.replace(~r/\/+$/, "")
          |> then(&expand_home/1)

        cond do
          forbidden?(real_path) ->
            {:error, "Forbidden path: #{real_path} is in a deny-listed zone (SSH, AWS, /etc, etc.)"}

          not File.exists?(real_path) ->
            {:error, "Path does not exist: #{real_path}"}

          not File.dir?(real_path) ->
            {:error, "Path is not a directory: #{real_path}"}

          not force? and sensitive?(real_path) and not has_project_marker?(real_path) ->
            {:error,
             "Path does not look like a project directory (no mix.exs, " <>
               "package.json, Cargo.toml, etc.). Use --force to override."}

          true ->
            :ok
        end
    end
  end

  @doc """
  Like `validate/2` but raises `ArgumentError` on failure.
  """
  def validate!(path, opts \\ []) do
    case validate(path, opts) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "Project path validation failed: #{reason}"
    end
  end

  defp expand_home("~" <> _ = path), do: Path.expand(path)
  defp expand_home(path), do: Path.expand(path)

  defp forbidden?(path) do
    Enum.any?(@forbidden_prefixes, fn prefix -> String.starts_with?(path, prefix) end)
  end

  defp sensitive?(path) do
    Enum.any?(@sensitive_prefixes, fn prefix -> String.starts_with?(path, prefix) end)
  end

  defp has_project_marker?(path) do
    Enum.any?(@project_markers, fn marker -> File.regular?(Path.join(path, marker)) end)
  end
end
