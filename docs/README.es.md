# Delfos

> Servidor MCP y herramienta de análisis de código para asistentes de IA.

Delfos indexa tu codebase, construye un grafo de símbolos y expone una API MCP
que los asistentes de IA (Claude Desktop, Cursor, Zed, etc.) usan para entender
tu código con precisión quirúrgica — sin alucinar sobre lo que no han visto.

## Características

- **Búsqueda híbrida** — vector semántico + BM25 + grafo con Reciprocal Rank Fusion
- **40+ lenguajes** — vía NIFs de Tree-sitter con fallback regex
- **Re-indexado en tiempo real** — Watcher detecta cambios y notifica al cliente MCP
- **Análisis de impacto BFS** — sabe qué se rompe antes de refactorizar
- **Métricas de deuda técnica** — churn, acoplamiento, inestabilidad, ciclos de dependencias
- **Multi-proveedor LLM** — local (OpenAI-compat), OpenAI, Anthropic

## Instalación

### Desde fuentes (recomendado para desarrollo)

```bash
git clone https://github.com/Lorenzo-SF/delfos
cd delfos
mix deps.get
mix compile
```

### Como binario (vía Batamanta)

Consulta la [página de releases](https://github.com/Lorenzo-SF/delfos/releases)
para escripts pre-construidos que incluyen Elixir y OTP — sin necesidad de
instalar Elixir localmente.

## Inicio rápido

```bash
# 1. Registrar un proyecto (cd al directorio primero)
cd /ruta/a/tu/proyecto
delfos init .

# 2. Scan completo (crea embeddings, construye grafo de símbolos)
delfos scan --full

# 3. (Opcional) Generar resúmenes LLM para símbolos
delfos summarize

# 4. Arrancar el servidor MCP
delfos serve --mcp
```

## Configuración MCP

### Claude Desktop (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "delfos": {
      "command": "/ruta/a/delfos",
      "args": ["serve", "--mcp"]
    }
  }
}
```

### Cursor / Zed

Configuración equivalente — apunta la entrada MCP al binario `delfos` con
`serve --mcp` como argumentos.

## Herramientas MCP disponibles

| Herramienta | Descripción |
|-------------|-------------|
| `delfos_search` | Búsqueda híbrida en el índice |
| `delfos_symbol` | Detalles completos de un símbolo con resumen LLM |
| `delfos_context` | Contexto compacto para una tarea |
| `delfos_callers` | Qué llama a un símbolo |
| `delfos_callees` | Qué llama un símbolo |
| `delfos_impact` | Análisis de impacto BFS antes de refactorizar |
| `delfos_audit` | Métricas de deuda técnica |
| `delfos_files` | Estructura de archivos indexados |

## Arquitectura

```
┌────────────────────────────────────────────────────────┐
│  MCP Server (JSON-RPC 2.0 sobre stdio)                │
│  └── Delfos.MCP.Tools (8 herramientas)                │
├────────────────────────────────────────────────────────┤
│  Indexer                                             │
│  ├── Scanner        (localiza archivos, SHA256)      │
│  ├── FileProcessor  (parsea + embed + persiste)      │
│  ├── GraphBuilder   (xref + grafo imports + ciclos)  │
│  └── Watcher        (FSEvents/inotify re-indexado)   │
├────────────────────────────────────────────────────────┤
│  Retrieval (paralelo vía Arrea)                      │
│  ├── HybridSearch  (vector + BM25 + grafo → RRF)     │
│  ├── VectorSearch  (coseno pgvector)                  │
│  ├── BM25Search    (PostgreSQL FTS)                   │
│  ├── GraphSearch   (BFS sobre grafo de símbolos)     │
│  └── Reranker      (Reciprocal Rank Fusion)          │
├────────────────────────────────────────────────────────┤
│  Parsers (40+ lenguajes)                             │
│  ├── TreeSitter NIF (Rust, basado en AST)            │
│  ├── Especializados (Dart, HCL, YAML)               │
│  └── GenericParser (fallback regex)                  │
├────────────────────────────────────────────────────────┤
│  LLM Client (multi-proveedor, multi-caso-uso)        │
│  ├── :local      (OpenAI-compat, llama.cpp)         │
│  ├── :openai     (OpenAI API)                        │
│  └── :anthropic  (Anthropic API)                     │
└────────────────────────────────────────────────────────┘
```

## Configuración

Delfos lee `~/.config/delfos/delfos.conf` (TOML) con override de variables de
entorno. Consulta `config/config.exs` para todas las opciones. Secciones
principales:

- `[embedding]` — proveedor, modelo, dimensión, batch size
- `[llm]` — proveedor LLM, modelo, max_tokens por caso de uso
- `[retrieval]` — pesos RRF, top_k, final_k
- `[indexing]` — directorios ignorados, max chunk tokens
- `[analysis]` — ventana de análisis de churn

## Ecosistema

Delfos forma parte del ecosistema OSS Elixir de Lorenzo-SF:

- **Arrea** — orquestador de procesos async (usado para retrieval paralelo)
- **Alaja** — framework de rendering terminal (usado para el CLI)
- **Candil** — inferencia LLM y gestión de modelos (usado para resúmenes)
- **Apero** — (ya no es dep runtime desde 2026-07; crypto AES-256-GCM
  inline sobre `:crypto` de Erlang)

## Cambios recientes

### v0.4.0 (2026-06-25) — CLI migrado al DSL `Alaja.CLI.Definition`

El dispatcher manual de 192 líneas en `Delfos.CLI.Main` se reemplaza por
un módulo declarativo `Delfos.CLI` que usa el DSL `Alaja.CLI.Definition`.

Cada subcomando se declara así:

```elixir
command "init", "Registrar proyecto y ejecutar primer escaneo completo" do
  argument(:path, :string, default: "")
  flag(:help, :boolean, [])
  run({Delfos.CLI, :init_handler})
end
```

16 comandos registrados: `init`, `scan`, `query`, `audit`, `summarize`,
`explain`, `graph`, `context`, `config`, `integrate`, `doctor`, `models`,
`status`, `watch`, `serve`, `version`.

Las funciones handler (p. ej. `init_handler/1`) hacen de puente entre el
mapa de opts del DSL y las signaturas existentes de
`Delfos.CLI.Commands.X.run/1`, así que las 13 implementaciones `run/1`
existentes no necesitaron reescribirse.

Nuevo: `test/delfos/cli/cli_test.exs` con 20 tests.

Dependencias bumpeadas:
- `alaja` → v0.3.3 (DSL seguro como librería)
- `pote` → `e0554d4` (trae `Pote.Theme`)
- `arrea` → v0.3.0 (compatibilidad con alaja v0.3.3)

### v0.3.4 (2026-06-25)
- README reescrito con comparativa de features y tabla CLI más clara.

### v0.3.3 (2026-06-25)
- 12 tests de verificación de formato para `delfos integrate`.

## Licencia

MIT — ver [LICENSE.md](LICENSE.md).
