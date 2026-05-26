defmodule Delfos.Parsers.Dispatcher do
  @moduledoc """
  Router de parsing basado en extensión.
  Tree-sitter cubre lenguajes de programación y IaC.
  Fallback a GenericParser solo para extensiones sin grammar disponible.
  """
  alias Delfos.Parsers.{TreeSitterParser, GenericParser}

  @parsers %{
    # Elixir / Erlang
    ".ex" => TreeSitterParser,
    ".exs" => TreeSitterParser,
    ".erl" => GenericParser,
    ".hrl" => GenericParser,
    # TypeScript / JavaScript / JSX
    ".ts" => TreeSitterParser,
    ".tsx" => TreeSitterParser,
    ".js" => TreeSitterParser,
    ".jsx" => TreeSitterParser,
    ".mjs" => TreeSitterParser,
    ".cjs" => TreeSitterParser,
    # PHP
    ".php" => GenericParser,
    # Python
    ".py" => TreeSitterParser,
    # Rust
    ".rs" => GenericParser,
    # Go
    ".go" => GenericParser,
    # Java / Kotlin / Scala / Groovy
    ".java" => GenericParser,
    ".kt" => GenericParser,
    ".kts" => GenericParser,
    ".scala" => GenericParser,
    ".groovy" => GenericParser,
    # C / C++ / Objective-C
    ".c" => GenericParser,
    ".h" => GenericParser,
    ".cpp" => GenericParser,
    ".cc" => GenericParser,
    ".cxx" => GenericParser,
    ".hpp" => GenericParser,
    ".m" => GenericParser,
    # C# / F# / VB
    ".cs" => GenericParser,
    ".fs" => GenericParser,
    ".fsx" => GenericParser,
    ".vb" => GenericParser,
    # Swift
    ".swift" => GenericParser,
    # Dart / Flutter
    ".dart" => TreeSitterParser,
    # Ruby
    ".rb" => GenericParser,
    # Lua
    ".lua" => GenericParser,
    # R
    ".r" => GenericParser,
    ".R" => GenericParser,
    # Julia
    ".jl" => GenericParser,
    # Perl
    ".pl" => GenericParser,
    ".pm" => GenericParser,
    # Bash / Shell / PowerShell
    ".sh" => GenericParser,
    ".bash" => GenericParser,
    ".zsh" => GenericParser,
    ".ps1" => GenericParser,
    ".psm1" => GenericParser,
    # Clojure
    ".clj" => GenericParser,
    ".cljs" => GenericParser,
    # Haskell
    ".hs" => GenericParser,
    # Assembly
    ".asm" => GenericParser,
    ".s" => GenericParser,
    # Terraform / HCL
    ".tf" => TreeSitterParser,
    ".hcl" => TreeSitterParser,
    # YAML / Config
    ".yaml" => TreeSitterParser,
    ".yml" => TreeSitterParser,
    # TOML / JSON (config-as-code)
    ".toml" => TreeSitterParser,
    ".json" => TreeSitterParser
  }

  @language_map %{
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".erl" => "erlang",
    ".hrl" => "erlang",
    ".ts" => "typescript",
    ".tsx" => "typescript",
    ".js" => "javascript",
    ".jsx" => "javascript",
    ".mjs" => "javascript",
    ".cjs" => "javascript",
    ".php" => "php",
    ".py" => "python",
    ".rs" => "rust",
    ".go" => "go",
    ".java" => "java",
    ".kt" => "kotlin",
    ".kts" => "kotlin",
    ".scala" => "scala",
    ".groovy" => "groovy",
    ".c" => "c",
    ".h" => "c",
    ".cpp" => "cpp",
    ".cc" => "cpp",
    ".cxx" => "cpp",
    ".hpp" => "cpp",
    ".m" => "objective-c",
    ".cs" => "csharp",
    ".fs" => "fsharp",
    ".fsx" => "fsharp",
    ".vb" => "vb",
    ".swift" => "swift",
    ".dart" => "dart",
    ".rb" => "ruby",
    ".lua" => "lua",
    ".r" => "r",
    ".R" => "r",
    ".jl" => "julia",
    ".pl" => "perl",
    ".pm" => "perl",
    ".sh" => "bash",
    ".bash" => "bash",
    ".zsh" => "bash",
    ".ps1" => "powershell",
    ".psm1" => "powershell",
    ".clj" => "clojure",
    ".cljs" => "clojure",
    ".hs" => "haskell",
    ".asm" => "assembly",
    ".s" => "assembly",
    ".tf" => "terraform",
    ".hcl" => "terraform",
    ".yaml" => "config",
    ".yml" => "config",
    ".toml" => "config",
    ".json" => "config"
  }

  def parse(path, content) do
    ext = Path.extname(path) |> String.downcase()
    parser = Map.get(@parsers, ext)

    case parser do
      nil -> {:error, :unsupported_extension}
      TreeSitterParser -> TreeSitterParser.parse(path, content)
      mod -> mod.parse(path, content)
    end
  end

  def supported?(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.has_key?(@parsers, ext)
  end

  def language(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.get(@language_map, ext, "unknown")
  end
end
