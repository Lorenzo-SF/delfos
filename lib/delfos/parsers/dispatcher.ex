defmodule Delfos.Parsers.Dispatcher do
  @moduledoc "Selecciona el parser correcto según la extensión del archivo."

  @parsers %{
    ".ex" => Delfos.Parsers.ElixirParser,
    ".exs" => Delfos.Parsers.ElixirParser,
    ".ts" => Delfos.Parsers.TypescriptParser,
    ".tsx" => Delfos.Parsers.TypescriptParser,
    ".js" => Delfos.Parsers.TypescriptParser,
    ".jsx" => Delfos.Parsers.TypescriptParser,
    ".py" => Delfos.Parsers.PythonParser
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
    case Path.extname(path) do
      ext when ext in ~w(.ex .exs) -> "elixir"
      ext when ext in ~w(.ts .tsx .js .jsx) -> "typescript"
      ".py" -> "python"
      ".rs" -> "rust"
      ".go" -> "go"
      _ -> "unknown"
    end
  end
end
