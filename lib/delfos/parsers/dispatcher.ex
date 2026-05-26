defmodule Delfos.Parsers.Dispatcher do
  @moduledoc """
  Router de parsing basado en extensión.
  Tree-sitter cubre lenguajes de programación y IaC.
  Fallback a GenericParser solo para extensiones sin grammar disponible.
  """
  alias Delfos.Parsers.{TreeSitterParser, GenericParser}

  @parsers %{
    ".ex" => TreeSitterParser,
    ".exs" => TreeSitterParser,
    ".erl" => GenericParser,
    ".hrl" => GenericParser,
    ".ts" => TreeSitterParser,
    ".tsx" => TreeSitterParser,
    ".js" => TreeSitterParser,
    ".jsx" => TreeSitterParser,
    ".mjs" => TreeSitterParser,
    ".cjs" => TreeSitterParser,
    ".py" => TreeSitterParser,
    ".dart" => TreeSitterParser,
    ".tf" => TreeSitterParser,
    ".hcl" => TreeSitterParser,
    ".yaml" => TreeSitterParser,
    ".yml" => TreeSitterParser,
    ".json" => TreeSitterParser,
    ".toml" => TreeSitterParser,
    ".rs" => GenericParser,
    ".go" => GenericParser,
    ".java" => GenericParser,
    ".kt" => GenericParser,
    ".c" => GenericParser,
    ".cpp" => GenericParser,
    ".rb" => GenericParser,
    ".lua" => GenericParser,
    ".sh" => GenericParser
  }

  @language_map %{
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".erl" => "erlang",
    ".ts" => "typescript",
    ".tsx" => "typescript",
    ".js" => "javascript",
    ".py" => "python",
    ".dart" => "dart",
    ".tf" => "terraform",
    ".hcl" => "terraform",
    ".yaml" => "config",
    ".yml" => "config",
    ".json" => "json",
    ".toml" => "toml",
    ".rs" => "rust",
    ".go" => "go",
    ".java" => "java",
    ".kt" => "kotlin",
    ".c" => "c",
    ".cpp" => "cpp",
    ".rb" => "ruby",
    ".lua" => "lua",
    ".sh" => "bash"
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
