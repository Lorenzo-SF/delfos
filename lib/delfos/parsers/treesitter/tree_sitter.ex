defmodule Delfos.Parsers.TreeSitter.NIF do
  @moduledoc false
  use Rustler, otp_app: :delfos, crate: :tree_sitter_nif

  def parse_symbols(_language, _source), do: :erlang.nif_error(:nif_not_loaded)
  def supported_languages(), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule Delfos.Parsers.TreeSitter do
  @moduledoc """
  Wrapper Elixir del NIF tree-sitter.

  Llama al NIF Rust para parsear con AST real y devuelve la misma
  estructura que los parsers regex (lista de mapas de símbolos).

  Si el NIF no está disponible o el lenguaje no está soportado,
  cae back automáticamente al GenericParser regex.

  Lenguajes con soporte AST completo:
    elixir, typescript, tsx, javascript, python, rust, go,
    java, csharp, c, cpp, php, ruby, swift, dart,
    scala, lua, bash
  """

  alias Delfos.Parsers.TreeSitter.NIF
  alias Delfos.Parsers.GenericParser

  @supported_languages ~w(
    elixir typescript tsx javascript python rust go
    java csharp c cpp php ruby swift dart scala lua bash
    haskell erlang ocaml clojure zig gleam julia hcl
    r kotlin objc asm fsharp
  )

  @doc """
  Parsea `content` con tree-sitter para el `language` dado.
  Devuelve `{:ok, %{symbols: [...], docs: [...], todos: [...], line_count: N}}`.
  """
  def parse(path, content, language) do
    lang_str = normalize_lang(language)

    if lang_str in @supported_languages do
      parse_with_nif(path, content, lang_str)
    else
      {:ok, GenericParser.parse(path, content)}
    end
  end

  def supported?(language), do: normalize_lang(language) in @supported_languages

  # ---------------------------------------------------------------------------
  # Privado
  # ---------------------------------------------------------------------------

  defp parse_with_nif(path, content, lang) do
    source = content

    case NIF.parse_symbols(lang, source) do
      {:ok, raw_symbols} ->
        symbols = Enum.map(raw_symbols, &normalize_symbol(&1, lang))
        lines = String.split(content, "\n")

        {:ok,
         %{
           symbols: symbols,
           docs: extract_doc_comments(content, lang),
           todos: extract_todos(lines),
           line_count: length(lines)
         }}

      {:error, reason} ->
        require Logger

        Logger.debug(
          "TreeSitter NIF falló para #{path} (#{lang}): #{reason}. Usando GenericParser."
        )

        {:ok, GenericParser.parse(path, content)}
    end
  rescue
    # A-1 audit fix: errores específicos en lugar de catch-all.
    # Si el NIF falla al cargar (por ejemplo en CI sin Rust), cae al regex parser.
    ArgumentError -> {:ok, GenericParser.parse(path, content)}
    ErlangError -> {:ok, GenericParser.parse(path, content)}
  end

  defp normalize_symbol(sym, lang) do
    %{
      name: sym["name"] || "",
      qualified_name: sym["qualified_name"] || sym["name"] || "",
      kind: sym["kind"] || "unknown",
      line_start: sym["line_start"] || 1,
      line_end: sym["line_end"] || 1,
      language: lang,
      visibility: sym["visibility"] || "public",
      signature: sym["signature"] || nil,
      metadata: %{}
    }
  end

  # Extrae comentarios de documentación por lenguaje
  defp extract_doc_comments(content, lang) do
    pattern =
      case lang do
        "elixir" ->
          ~r{@(?:moduledoc|doc)\s+"""\n(.*?)"""}s

        "python" ->
          ~r{"""(.*?)"""}s

        "rust" ->
          ~r{///\s*(.*)}

        "go" ->
          ~r{//\s*(.*)}

        l when l in ["typescript", "javascript", "tsx", "java", "kotlin", "csharp", "php"] ->
          ~r{/\*\*\s*(.*?)\s*\*/}s

        _ ->
          ~r{//!?\s*(.*)}
      end

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, doc] -> String.trim(doc) end)
    |> Enum.filter(&(String.length(&1) > 10))
  rescue
    # A-6 audit fix: errores de regex mal formado son bugs; log y devolver [].
    ArgumentError -> []
  end

  defp extract_todos(lines) do
    todo_re = ~r{(?://|#|--)\s*(TODO|FIXME|HACK|XXX|DEBT)\b.*}i

    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end

  defp normalize_lang("elixir"), do: "elixir"
  # fallback razonable
  defp normalize_lang("erlang"), do: "elixir"
  defp normalize_lang("typescript"), do: "typescript"
  defp normalize_lang("javascript"), do: "javascript"
  defp normalize_lang("python"), do: "python"
  defp normalize_lang("rust"), do: "rust"
  defp normalize_lang("go"), do: "go"
  defp normalize_lang("java"), do: "java"
  defp normalize_lang("csharp"), do: "csharp"
  defp normalize_lang("c"), do: "c"
  defp normalize_lang("cpp"), do: "cpp"
  defp normalize_lang("php"), do: "php"
  defp normalize_lang("ruby"), do: "ruby"
  defp normalize_lang("swift"), do: "swift"
  defp normalize_lang("dart"), do: "dart"
  defp normalize_lang("scala"), do: "scala"
  defp normalize_lang("lua"), do: "lua"
  defp normalize_lang("bash"), do: "bash"
  defp normalize_lang("powershell"), do: "bash"
  # Aliases: dispatcher canonical name → NIF atom
  defp normalize_lang("objective-c"), do: "objc"
  defp normalize_lang("assembly"), do: "asm"
  defp normalize_lang(other), do: other
end
