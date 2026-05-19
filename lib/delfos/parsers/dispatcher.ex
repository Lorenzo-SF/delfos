defmodule Delfos.Parsers.Dispatcher do
  @moduledoc """
  Selecciona el parser correcto según la extensión del archivo.

  El mapa `@parsers` y la función `language/1` están sincronizados:
  toda extensión reconocida en `language/1` tiene su entrada en `@parsers`,
  aunque apunte a un parser genérico cuando no hay implementación específica.
  """

  alias Delfos.Parsers.{ElixirParser, TypescriptParser, PythonParser, GenericParser}

  @parsers %{
    ".ex" => ElixirParser,
    ".exs" => ElixirParser,
    ".ts" => TypescriptParser,
    ".tsx" => TypescriptParser,
    ".js" => TypescriptParser,
    ".jsx" => TypescriptParser,
    ".py" => PythonParser,
    ".rs" => GenericParser,
    ".go" => GenericParser
  }

  @language_map %{
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".ts" => "typescript",
    ".tsx" => "typescript",
    ".js" => "typescript",
    ".jsx" => "typescript",
    ".py" => "python",
    ".rs" => "rust",
    ".go" => "go"
  }

  def parse(path, content) do
    ext = Path.extname(path)

    case Map.get(@parsers, ext) do
      nil -> {:error, :unsupported_extension}
      parser -> {:ok, parser.parse(path, content)}
    end
  end

  def supported?(path), do: Map.has_key?(@parsers, Path.extname(path))

  def language(path) do
    Map.get(@language_map, Path.extname(path), "unknown")
  end
end
