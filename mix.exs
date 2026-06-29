defmodule Delfos.MixProject do
  use Mix.Project

  @version "0.4.10"
  @source_url "https://github.com/Lorenzo-SF/delfos"
  @elixir_vsn "1.19.5"
  @erlang_vsn "28.0"
  @otp_vsn "28"
  @binary_name :delfos

  def project do
    [
      app: @binary_name,
      version: @version,
      elixir: "~> #{@elixir_vsn}",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      escript: escript(),
      releases: releases(),
      batamanta: batamanta(),
      rustler_crates: rustler_crates()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Delfos.Application, []}
    ]
  end

  defp escript, do: [main_module: Delfos.CLI, name: "delfos"]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "priv"],
      maintainers: ["Lorenzo-SF"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp deps do
    [
      {:alaja, path: "../alaja", override: true},
      {:arrea, github: "Lorenzo-SF/arrea"},
      {:apero, github: "Lorenzo-SF/apero"},
      {:botica, github: "Lorenzo-SF/botica"},
      {:candil, path: "../candil"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:pgvector, "~> 0.3"},
      # {:optimus, "~> 0.3"},
      # {:owl, "~> 0.12"},
      {:req, "~> 0.5"},
      {:file_system, "~> 1.0"},
      # {:flow, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:toml, "~> 0.7"},
      {:tree_sitter, "~> 0.0.3", runtime: false},
      {:rustler, "~> 0.34.0", runtime: false},
      {:batamanta, "~> 1.5", runtime: false},
      {:mix_test_watch, "~> 1.1", only: :dev, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/README.es.md",
        "CHANGELOG.md",
        "SPEC.md",
        "docs/MCP_TOOLS.md",
        "CONTRIBUTING.md"
      ],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp aliases do
    [
      gen: ["compile", "release --overwrite", "deploy", "tools_version"],
      quality: [
        "format",
        "compile --warnings-as-errors",
        "test",
        "credo --strict --format=oneline",
        "run bench",
        "coveralls",
        "dialyzer"
      ],
      setup: ["deps.get", "cmd mix dialyzer --plt"],
      "test.coverage": ["test --cover"],
      lint: ["format --check-formatted", "credo --strict"],
      "lint.fix": ["format", "credo --strict"],
      deploy: fn _ ->
        src = Path.expand(Path.join(["_build", "prod", "rel", "delfos", "bin", "delfos-cli"]))
        dest_dir = Path.expand("~/bin")
        dest = Path.join(dest_dir, "delfos")
        File.mkdir_p!(dest_dir)
        File.rm_rf(dest)
        File.cp!(src, dest)
        File.chmod!(dest, 0o755)
        Mix.shell().info("✅  Release CLI instalado en #{dest}")
      end,
      tools_version: fn _ ->
        dest_dir = Path.expand("~/bin")
        path = Path.join(dest_dir, ".tool-versions")
        File.write!(path, "erlang #{@erlang_vsn}\nelixir #{@elixir_vsn}-otp-#{@otp_vsn}\n")
        Mix.shell().info("✅  .tool-versions actualizado.")
      end,
      db: ["ecto.create", "ecto.migrate"],
      db_reset: ["ecto.drop", "db"]
    ]
  end

  defp batamanta do
    [
      format: :escript,
      execution_mode: :cli,
      compression: 1,
      binary_name: Atom.to_string(@binary_name)
    ]
  end

  defp rustler_crates do
    [
      tree_sitter_nif: Path.join(__DIR__, "native/tree_sitter_nif")
    ]
  end

  defp releases do
    [
      delfos: [
        include_erts: false,
        steps: [:assemble, &embed_release/1],
        applications: [
          delfos: :permanent,
          alaja: :permanent,
          arrea: :permanent,
          apero: :permanent,
          botica: :permanent,
          candil: :transient
        ]
      ]
    ]
  end

  defp embed_release(%{path: path} = release) do
    release_bin = Path.join(path, "bin/delfos")
    wrapper =
      ~S"""
      #!/bin/sh
      case "${1:-}" in
        start|stop|pid|remote|restart|eval|rpc|ping|attach|console|daemon|upgrade|downgrade|install|uninstall|describe|spawn)
          exec __RELEASE_BIN__ "$@"
          ;;
      esac
      args=""
      sep=""
      for a in "$@"; do
        esc=$(printf "%s" "$a" | sed 's/"/\\"/g')
        args="$args$sep\"$esc\""
        sep=", "
      done
      exec __RELEASE_BIN__ eval "Delfos.CLI.main([$args])"
      """
      |> String.replace("__RELEASE_BIN__", release_bin)

    wrapper_path = Path.join(path, "bin/delfos-cli")
    File.write!(wrapper_path, wrapper)
    File.chmod!(wrapper_path, 0o755)
    release
  end
end
