📦 PROMPT 2: Motor de Parsing Basado en AST & Resolución Framework-Aware
Contexto: Los parsers actuales usan regex. Fallan con código anidado, decoradores complejos, macros y patrones dinámicos. find_line_end/3 es heurístico y corta símbolos en proyectos reales.
Objetivo: Migrar a Tree-sitter (WASM o NIF), extraer símbolos con scope-aware resolution, generar qualified_name correcto, y añadir resolvers para Phoenix, NestJS, FastAPI y Django.
Requisitos Técnicos:
Integrar :tree_sitter (NIF) o tree_sitter_wasm (más seguro, menor overhead de build).
Crear Delfos.Parsers.TreeSitterParser con queries S-expression por lenguaje.
Resolver nombres calificados usando scope stack (módulo/clase/función actual).
Implementar find_line_end vía node.range de Tree-sitter (preciso al carácter).
Añadir Delfos.Resolvers.FrameworkResolver con patrones para:
Phoenix: get "/path", Controller, :action → edge route → controller_action
NestJS: @Controller('users') + @Get('') → edge route → method
FastAPI: @router.get("/x") → edge route → handler
Django: path('x/', views.MyView.as_view()) → edge route → view
Pasos de Implementación:
# 1. Parser base
defmodule Delfos.Parsers.TreeSitterParser do
  def parse(path, content) do
    lang = Dispatcher.language(path)
    grammar = load_grammar(lang)
    tree = TreeSitter.parse(grammar, content)
    query = load_query(lang)
    matches = TreeSitter.query_matches(tree, query)
    %{
      symbols: extract_symbols(matches, content, path),
      docs: extract_docs(matches),
      todos: extract_todos(content),
      line_count: count_lines(content)
    }
  end

  defp extract_symbols(matches, content, path) do
    # Usa TreeSitter.node_text/2, node_range/1, y scope_stack para qualified_name
    # Retorna lista de %{name, qualified_name, kind, line_start, line_end, visibility, content}
  end
end

# 2. Framework resolver (post-extracción)
defmodule Delfos.Resolvers.FrameworkResolver do
  def resolve_routes(symbols, project) do
    symbols
    |> Enum.filter(& &1.kind == "route")
    |> Enum.map(&resolve_route_target(&1, symbols))
  end
  # Patrones regex ligeros sobre docstring/signature para mapear a controladores
end
Criterios de Aceptación:
delfos scan en proyecto Phoenix extrae UserController.index con line_start/line_end exactos
qualified_name es MyAppWeb.UserController.index (no index)
Tests con código Elixir anidado (defmacro __using__, with, case) no cortan símbolos
delfos graph callers UserController.index muestra rutas que lo invocan
Parser fallback a regex si Tree-sitter no está compilado (compatibilidad backwards)
Dependencias: :tree_sitter o tree_sitter_wasm, grammars .wasm o compilados, :nimble_parsec (opcional para fallback)