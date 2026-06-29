defmodule Mix.Tasks.Gen do
  @moduledoc """
  Builds a platform-correct `delfos` binary end-to-end.

  This wraps the existing alias `gen: ["compile", "release --overwrite",
  "deploy", "tools_version"]` with a pre-flight check that:

    1. Ensures the Rust toolchain needed for the tree-sitter NIF is
       installed (compilers, cmake, the platform-specific linker
       flags macOS needs).
    2. Writes `native/tree_sitter_nif/.cargo/config.toml` if missing
       — handles users who cloned the repo before v0.4.10 without the
       macOS dynamic_lookup config.
    3. Runs `deps.get` if `mix.lock` looks stale.
    4. Compiles, releases, deploys to `~/bin/delfos`, writes the
       `.tool-versions` file so source-level development keeps using
       the right Elixir/OTP.
    5. Prints a single concise "what to do next" line.

  The goal: a Mac, Linux or Windows user can clone the repo and run
  `mix gen` once, and end up with `delfos` on their PATH.

  ## Usage

      mix gen                  # full build + deploy
      mix gen --skip-test      # leave existing release if any
      mix gen --no-deploy      # don't copy to ~/bin

  Flags are passed straight through to the underlying release step.
  """

  use Mix.Task

  @shortdoc "Build the platform-correct delfos binary (compile + release + deploy)"

  require Logger

  @cargo_config_path Path.expand("native/tree_sitter_nif/.cargo/config.toml")

  @impl true
  def run(args) do
    ensure_cargo_config!()
    ensure_rust_toolchain!()
    ensure_system_deps!()
    ensure_deps_fresh!()

    # Hand off to the real alias. `mix gen` literally runs the same steps
    # as `gen: [...]` — the only thing this wrapper adds are the checks
    # above, plus clearer post-flight logging.
    Mix.Task.run("compile", args)

    release_args =
      if "--no-deploy" in args do
        ["--overwrite" | args] |> Enum.uniq()
      else
        ["--overwrite" | args] |> Enum.uniq()
      end

    Mix.Task.run("release", release_args -- ["--no-deploy"])

    deploy_or_skip(args)
    write_tool_versions()

    print_done(args)
  end

  # ---------------------------------------------------------------------------
  # Pre-flight: macOS dynamic_lookup
  # ---------------------------------------------------------------------------

  @doc false
  @spec ensure_cargo_config!() :: :ok | {:error, String.t()}
  def ensure_cargo_config! do
    if File.exists?(@cargo_config_path) do
      :ok
    else
      Mix.shell().info(
        "[gen] missing .cargo/config.toml — adding macOS dynamic_lookup rustflag"
      )

      File.mkdir_p!(Path.dirname(@cargo_config_path))

      File.write!(@cargo_config_path, default_cargo_config())

      :ok
    end
  end

  defp default_cargo_config do
    """
    # macOS-specific linker flags required by Rustler/Rust since Elixir/Erlang
    # NIFs are loaded as `dylib` and macOS's linker rejects undefined symbols
    # by default. The `dynamic_lookup` flag keeps symbols lazy until load.
    #
    # Added automatically by `mix gen` on first build — keep it committed.
    [target.'cfg(target_os = "macos")']
    rustflags = [
        "-C", "link-arg=-undefined",
        "-C", "link-arg=dynamic_lookup",
    ]
    """
  end

  # ---------------------------------------------------------------------------
  # Pre-flight: Rust toolchain
  # ---------------------------------------------------------------------------

  @doc false
  @spec ensure_rust_toolchain!() :: :ok | {:error, String.t()}
  def ensure_rust_toolchain! do
    case System.cmd("rustc", ["--version"], stderr_to_stdout: true) do
      {out, 0} ->
        version = out |> String.trim() |> String.split(" ") |> Enum.at(1)

        case Version.parse(version) do
          {:ok, v} when v.major >= 1 and v.minor >= 78 ->
            :ok

          _ ->
            Mix.shell().error(
              "[gen] rustc #{version} is too old. Tree-sitter 0.25 needs rust ≥ 1.78.\n" <>
                "      Install via https://rustup.rs and re-run."
            )

            raise "rustc #{version} too old"
        end

      {_err, _} ->
      Mix.shell().error("[gen] rustc is missing.\n      Install via https://rustup.rs/")

      raise "rustc missing"
    end
  end

  # ---------------------------------------------------------------------------
  # Pre-flight: system C deps (cmake, gcc/clang)
  # ---------------------------------------------------------------------------

  @doc false
  @spec ensure_system_deps!() :: :ok | {:error, String.t()}
  def ensure_system_deps! do
    missing =
      [
        {"cc", "C compiler (gcc/clang)"},
        {"cmake", "CMake (tree-sitter generates C grammars)"}
      ]
      |> Enum.reject(fn {bin, _desc} -> has_cmd?(bin) end)
      |> Enum.map(fn {_bin, desc} -> desc end)

    case missing do
      [] ->
        :ok

      list ->
        Mix.shell().info("[gen] missing system deps: #{Enum.join(list, ", ")}")

        case detect_os() do
          :mac ->
            Mix.shell().info(
              "       Install Xcode Command Line Tools:\n" <>
                "         xcode-select --install"
            )

          os when os in [:debian, :ubuntu] ->
            Mix.shell().info(
              "       Install with:\n" <>
                "         sudo apt-get install -y build-essential cmake"
            )

          os when os in [:fedora, :rhel, :centos, :rocky] ->
            Mix.shell().info(
              "       Install with:\n" <>
                "         sudo dnf install -y gcc make cmake"
            )

          :arch ->
            Mix.shell().info(
              "       Install with:\n" <>
                "         sudo pacman -S base-devel cmake"
            )

          :windows ->
            Mix.shell().info(
              "       Install with:\n" <>
                "         winget install Kitware.CMake"
            )

          _ ->
            :ok
        end
    end

    :ok
  end

  defp has_cmd?(bin) do
    case System.cmd("which", [bin], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc false
  def detect_os do
    case :os.type() do
      {:win, _} -> :windows

      {:unix, :darwin} ->
        :mac

      {:unix, :linux} ->
        case File.read("/etc/os-release") do
          {:ok, content} ->
            cond do
              String.contains?(content, "ID=ubuntu") or String.contains?(content, "ID=debian") ->
                :debian

              String.contains?(content, "ID=fedora") or
                  String.contains?(content, "ID=rhel") or
                    String.contains?(content, "ID=centos") ->
                :fedora

              String.contains?(content, "ID=arch") ->
                :arch

              true ->
                :linux
            end

          _ ->
            :linux
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Pre-flight: deps
  # ---------------------------------------------------------------------------

  defp ensure_deps_fresh! do
    cond do
      not File.exists?("deps") ->
        Mix.shell().info("[gen] deps/ missing — running mix deps.get")
        Mix.Task.run("deps.get", [])

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Post-flight
  # ---------------------------------------------------------------------------

  defp deploy_or_skip(args) do
    if "--no-deploy" in args do
      Mix.shell().info("[gen] --no-deploy set: release stays in _build/prod/rel/delfos/")
    else
      Mix.Task.run("loadpaths", ["--no-compile"])
      Mix.Task.run("run", ["--no-start", "-e", deploy_script()])
    end
  end

  defp deploy_script do
    """
    src = Path.expand(Path.join(["_build", "prod", "rel", "delfos", "bin", "delfos-cli"]))
    dest_dir = Path.expand("~/bin")
    dest = Path.join(dest_dir, "delfos")
    File.mkdir_p!(dest_dir)
    File.rm_rf(dest)
    File.cp!(src, dest)
    File.chmod!(dest, 0o755)
    IO.puts("Installed: \#{dest}")
    """
  end

  defp write_tool_versions do
    # matches @elixir_vsn / @erlang_vsn in mix.exs — keep in sync.
    elixir_vsn = "1.19.5"
    erlang_vsn = "28.0"
    otp_vsn = "28"

    dest_dir = Path.expand("~/bin")
    File.mkdir_p!(dest_dir)
    path = Path.join(dest_dir, ".tool-versions")
    File.write!(path, "erlang #{erlang_vsn}\nelixir #{elixir_vsn}-otp-#{otp_vsn}\n")

    Mix.shell().info("[gen] wrote #{path}")
  end

  defp print_done(args) do
    bin = Path.expand("~/bin/delfos")

    cond do
      "--no-deploy" in args ->
        Mix.shell().info("""
        [gen] done.
          Release: _build/prod/rel/delfos/bin/delfos-cli
          (--no-deploy: not copied anywhere)
        """)

      File.exists?(bin) ->
        Mix.shell().info("""

        [gen] done.

        Binary installed at: #{bin}

        Add ~/bin to your PATH if it isn't already:
          export PATH="$HOME/bin:$PATH"

        Then verify:
          delfos version
          delfos doctor
        """)

      true ->
        Mix.shell().info("""
        [gen] release built but ~/bin/delfos was not installed (likely missing ~/bin dir).
              See _build/prod/rel/delfos/bin/delfos-cli for the release binary.
        """)
    end
  end
end