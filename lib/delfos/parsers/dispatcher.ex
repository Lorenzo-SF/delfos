defmodule Delfos.Parsers.Dispatcher do
  @moduledoc """
  Selecciona el parser correcto para cada extensión.

  Orden de prioridad:
    1. TreeSitter NIF — AST real para lenguajes soportados
    2. Parsers especializados — Dart, HCL, YAML
    3. GenericParser regex — fallback
  """

  alias Delfos.Parsers.{TreeSitter, DartParser, HCLParser, YAMLParser, GenericParser}

  # Known binary/content extensions that should never be parsed.
  # These return {:error, :unsupported_extension} instead of falling
  # through to GenericParser.
  @binary_extensions MapSet.new([
                       ".png",
                       ".jpg",
                       ".jpeg",
                       ".gif",
                       ".bmp",
                       ".webp",
                       ".ico",
                       ".svg",
                       ".pdf",
                       ".doc",
                       ".docx",
                       ".xls",
                       ".xlsx",
                       ".ppt",
                       ".pptx",
                       ".zip",
                       ".tar",
                       ".gz",
                       ".tgz",
                       ".bz2",
                       ".xz",
                       ".zst",
                       ".7z",
                       ".rar",
                       ".mp3",
                       ".mp4",
                       ".wav",
                       ".flac",
                       ".ogg",
                       ".avi",
                       ".mkv",
                       ".mov",
                       ".woff",
                       ".woff2",
                       ".ttf",
                       ".otf",
                       ".eot",
                       ".so",
                       ".dylib",
                       ".dll",
                       ".exe",
                       ".o",
                       ".a",
                       ".lib",
                       ".class",
                       ".jar",
                       ".wasm",
                       ".db",
                       ".sqlite",
                       ".sqlite3"
                     ])

  @language_map %{
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".erl" => "erlang",
    ".hrl" => "erlang",
    ".gleam" => "gleam",
    ".ts" => "typescript",
    ".tsx" => "tsx",
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
    ".gvy" => "groovy",
    ".gy" => "groovy",
    ".gsh" => "groovy",
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
    ".psd1" => "powershell",
    ".clj" => "clojure",
    ".cljs" => "clojure",
    ".hs" => "haskell",
    ".ml" => "ocaml",
    ".mli" => "ocaml",
    ".zig" => "zig",
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
    lang = Map.get(@language_map, ext, "unknown")

    result =
      cond do
        ext in [".dart"] -> {:ok, DartParser.parse(path, content)}
        ext in [".tf", ".hcl"] -> {:ok, HCLParser.parse(path, content)}
        ext in [".yaml", ".yml"] -> {:ok, YAMLParser.parse(path, content)}
        TreeSitter.supported?(lang) -> TreeSitter.parse(path, content, lang)
        MapSet.member?(@binary_extensions, ext) -> {:error, :unsupported_extension}
        true -> {:ok, GenericParser.parse(path, content)}
      end

    with {:ok, parsed} <- result do
      {:ok, Map.put(parsed, :language, lang)}
    end
  end

  def supported?(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.has_key?(@language_map, ext)
  end

  def language(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.get(@language_map, ext, "unknown")
  end
end
