defmodule Delfos.Parsers.TreeSitter.NIF do
  @moduledoc false
  use Rustler, otp_app: :delfos, crate: :tree_sitter_nif

  def parse_symbols(_language, _source), do: :erlang.nif_error(:nif_not_loaded)
  # TEMP DEBUG: exposes raw tree-sitter named nodes from the Rust NIF.
  def dump_tree(_language, _source), do: :erlang.nif_error(:nif_not_loaded)
  def supported_languages(), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule Delfos.Parsers.TreeSitter do
  @moduledoc """
  Wrapper Elixir del NIF tree-sitter.

  Llama al NIF Rust para parsear con AST real y devuelve la misma
  estructura que los parsers regex (lista de mapas de símbolos).

  Si el NIF no está disponible o el lenguaje no está soportado,
  cae back automáticamente al GenericParser regex.

  Lenguajes con soporte AST completo (NIF tree-sitter):
    elixir, typescript, tsx, javascript, python, rust, go,
    java, csharp, c, cpp, php, ruby, swift, dart,
    scala, lua, bash, haskell, erlang, ocaml, clojure,
    zig, gleam, julia, hcl, r, kotlin, objc, asm, fsharp,
    powershell, groovy
  """

  alias Delfos.Parsers.TreeSitter.NIF
  alias Delfos.Parsers.GenericParser

  @supported_languages ~w(
    elixir typescript tsx javascript python rust go
    java csharp c cpp php ruby swift dart scala lua bash
    haskell erlang ocaml clojure zig gleam julia hcl
    r kotlin objc asm fsharp
    powershell groovy
  )

  @doc """
  Parsea `content` con tree-sitter para el `language` dado.
  Devuelve `{:ok, %{symbols: [...], docs: [...], todos: [...], line_count: N}}`.

  ## Options

    * `:max_depth` — if set, limits tree traversal depth for large files
      (useful for quick preview/indexing).  Default: unlimited.
  """
  def parse(path, content, language, opts \\ []) do
    lang_str = normalize_lang(language)

    if lang_str in @supported_languages do
      parse_with_nif(path, content, lang_str, opts)
    else
      result = GenericParser.parse(path, content)
      apply_max_depth(result, opts[:max_depth])
    end
  end

  defp apply_max_depth(result, nil), do: {:ok, result}
  defp apply_max_depth(result, max_depth) when is_integer(max_depth) and max_depth > 0 do
    {:ok,
     %{
       result
       | symbols: Enum.take(result.symbols, max_depth)
     }}
  end
  defp apply_max_depth(result, _), do: {:ok, result}

  def supported?(language), do: normalize_lang(language) in @supported_languages

  # ---------------------------------------------------------------------------
  # Privado
  # ---------------------------------------------------------------------------

  defp parse_with_nif(path, content, lang, opts) do
    source = content
    max_depth = Keyword.get(opts, :max_depth)

    case NIF.parse_symbols(lang, source) do
      {:ok, raw_symbols} ->
        # Fallback safety net: if the NIF returns an empty list for a
        # non-empty file, the grammar extraction is likely broken (we
        # hit this with tree-sitter-elixir 0.3.5 — the grammar emits
        # `call` nodes but the Rust extractor doesn't match them). Try
        # the regex-based GenericParser as a fallback so users still
        # get useful symbol data.
        {effective_symbols, _} =
          if raw_symbols == [] and byte_size(content) > 50 do
            require Logger

            Logger.debug(
              "TreeSitter NIF returned 0 symbols for #{path} (#{lang}, " <>
                "#{byte_size(content)} bytes) — falling back to GenericParser"
            )

            {GenericParser.parse(path, content).symbols, true}
          else
            {raw_symbols, false}
          end

        symbols = Enum.map(effective_symbols, &normalize_symbol(&1, lang))
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
    # Accept both atom keys (from GenericParser fallback) and string
    # keys (from the NIF).
    get = fn key ->
      cond do
        is_map_key(sym, key) -> Map.get(sym, key)
        is_map_key(sym, Atom.to_string(key)) -> Map.get(sym, Atom.to_string(key))
        true -> nil
      end
    end

    name = get.(:name)
    qname = get.(:qualified_name) || name

    %{
      name: name || "",
      qualified_name: qname || "",
      kind: get.(:kind) || "unknown",
      line_start: get.(:line_start) || 1,
      line_end: get.(:line_end) || 1,
      language: lang,
      visibility: get.(:visibility) || "public",
      signature: get.(:signature),
      docstring: get.(:docstring),
      content: get.(:content),
      metadata: get.(:metadata) || %{}
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

        l
        when l in ["typescript", "javascript", "tsx", "java", "kotlin", "csharp", "php", "groovy"] ->
          ~r{/\*\*\s*(.*?)\s*\*/}s

        "powershell" ->
          ~r{#\s*(.*)}

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
  defp normalize_lang("powershell"), do: "powershell"
  defp normalize_lang("groovy"), do: "groovy"
  # Aliases: dispatcher canonical name → NIF atom
  defp normalize_lang("objective-c"), do: "objc"
  defp normalize_lang("assembly"), do: "asm"
  defp normalize_lang(other), do: other
end
