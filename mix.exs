defmodule Delfos.MixProject do
  use Mix.Project

  @version "2.1.0"
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
      extra_applications: [:logger, :crypto, :inets],
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
    # Local-projects: use `path:` for faster iteration when the sibling
    # directory exists; fall back to GitHub `main` in CI or clean clones.
    # This matches the pattern used by `batamanta_dep/0` below.
    # Apero was removed in 2.0.1 — all functionality replaced by stdlib.
    [
      alaja_dep(),
      candil_dep(),
      arrea_dep(),
      botica_dep(),
      batamanta_dep(),
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:pgvector, "~> 0.3"},
      {:req, "~> 0.6", override: true},
      {:file_system, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:toml, "~> 0.7"},
      {:tree_sitter, "~> 0.0.3", runtime: false},
      {:rustler, "~> 0.34.0", runtime: false},
      {:mix_test_watch, "~> 1.1", only: :dev, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  # Local-project helpers — each checks if the sibling dir exists and
  # uses `path:` for dev, falling back to GitHub `main` otherwise.

  defp alaja_dep do
    if File.dir?("../alaja") do
      {:alaja, path: "../alaja", override: true}
    else
      {:alaja, "~> 2.0.0", override: true}
    end
  end

  defp candil_dep do
    if File.dir?("../candil") do
      {:candil, path: "../candil", override: true}
    else
      {:candil, github: "Lorenzo-SF/candil", branch: "main"}
    end
  end

  defp arrea_dep do
    if File.dir?("../arrea") do
      {:arrea, path: "../arrea", override: true}
    else
      {:arrea, github: "Lorenzo-SF/arrea", branch: "main"}
    end
  end

  defp botica_dep do
    if File.dir?("../botica") do
      {:botica, path: "../botica", override: true}
    else
      {:botica, github: "Lorenzo-SF/botica", branch: "main"}
    end
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
      source_ref: "1.0.0"
    ]
  end

  defp aliases do
    [
      # `mix gen` is the canonical end-to-end build: it runs `mix
      # batamanta` to produce the platform-aware release, then
      # `mix deploy` to copy the resulting binary into `~/bin/delfos`
      # so the user can just `delfos` it. The pre-flight checks
      # (rust toolchain, .cargo/config.toml, deps freshness) live
      # inside the `batamanta` task itself.
      gen: ["batamanta", "deploy"],
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
      # `mix deploy` copies the batamanta-generated release binary
      # into `~/bin/delfos` so it's on the user's PATH. The previous
      # version pointed at the Mix-release wrapper `delfos-cli`,
      # which is now obsolete — `mix batamanta` produces the final
      # binary directly in the project root.
      deploy: fn _ ->
        # `mix batamanta` writes the assembled binary next to mix.exs
        # so users can find it without digging through _build/. For
        # backward compatibility we also accept the legacy path.
        candidates = [
          Path.expand("delfos"),
          Path.expand(Path.join(["_build", "prod", "rel", "delfos", "bin", "delfos"]))
        ]

        src =
          Enum.find(candidates, fn p ->
            File.exists?(p) and not File.dir?(p)
          end)

        if is_nil(src) do
          Mix.shell().error(
            "[deploy] could not find a delfos binary. Tried:\n" <>
              Enum.map_join(candidates, "\n", &"  - #{&1}") <>
              "\nRun `mix batamanta` first."
          )
        else
          dest_dir = Path.expand("~/bin")
          dest = Path.join(dest_dir, "delfos")
          File.mkdir_p!(dest_dir)
          File.rm_rf(dest)
          File.cp!(src, dest)
          File.chmod!(dest, 0o755)
          Mix.shell().info("✅  Release CLI installed at #{dest} (from #{src})")
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

  defp batamanta_dep do
    # Use local path for dev (faster iteration), hex release otherwise
    if File.dir?("../batamanta") do
      {:batamanta, path: "../batamanta", runtime: false, override: true}
    else
      {:batamanta, "~> 1.6.1", runtime: false, override: true}
    end
  end

  defp batamanta do
    [
      # `:release` (not `:escript`) is required because tree-sitter is
      # a Rust NIF, and escripts cannot include NIFs. The previous
      # `:escript` config silently dropped libtree_sitter_nif.so at
      # bundle time, so the resulting binary crashed with
      # `cannot open shared object file` and fell back to the regex
      # GenericParser.
      format: :release,
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
        steps: [:assemble, :tar],
        applications: [
          delfos: :permanent,
          alaja: :permanent,
          arrea: :permanent,
          botica: :permanent,
          candil: :transient
        ]
      ]
    ]
  end
end
