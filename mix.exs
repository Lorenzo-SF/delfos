defmodule Delfos.MixProject do
  use Mix.Project

  @version "0.4.5"
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
      batamanta: batamanta()
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
      {:candil, github: "Lorenzo-SF/candil"},
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
      gen: ["compile", "batamanta", "deploy", "tools_version"],
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
        dest_dir = Path.expand("~/bin")
        File.mkdir_p!(dest_dir)

        case File.cp("delfos", Path.join(dest_dir, "delfos")) do
          :ok ->
            File.chmod!(Path.join(dest_dir, "delfos"), 0o755)
            Mix.shell().info("✅  Escript instalado en #{dest_dir}/delfos. ")

          {:error, _} ->
            Mix.shell().error("❌ [ERROR] No se pudo copiar el ejecutable.")
        end
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

  defp releases do
    [
      delfos: [
        steps: [:assemble, :tar],
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
end
