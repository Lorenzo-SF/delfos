defmodule Delfos.Repo.Migrations.DedupOrphanElixirSymbols do
  use Ecto.Migration

  @moduledoc """
  Limpia filas huérfanas en `symbols` dejadas por el NIF viejo de
  tree-sitter-elixir antes del fix `30e9b48` (Bug #22, ver CHANGELOG).

  ## Background

  El NIF viejo (commit anterior a `30e9b48`) devolvía `[]` para archivos
  `.ex` / `.exs`, así que para archivos >50 bytes el dispatcher caía en
  un parser regex genérico. Ese fallback perdía el contexto del prefijo
  de módulo y almacenaba cada `def foo` con `qualified_name = "foo"` en
  lugar de `"Module.foo"`.

  Tras el fix, el NIF nuevo escribe correctamente
  `qualified_name = "Module.foo"` para la misma función. La clave de
  `upsert_symbol` es `(file_id, name, line_start)`; cuando `line_start`
  difiere entre los dos parses (regex vs NIF), coexisten ambas filas →
  duplicados.

  El filtro apunta exactamente a esos huérfanos:

    1. `qualified_name = name` — sin prefijo de módulo, firma inequívoca
       del fallback regex.
    2. `kind IN ('function', 'macro', 'type', 'callback', 'behaviour',
       'use')` — los kinds que el fallback emitía.
    3. `EXISTS (sibling con mismo file_id/name, qn LIKE '%.<name>')` —
       confirma que existe la versión prefijada (la canónica del NIF
       nuevo) antes de borrar. Sin esto, una fila huérfana sin hermano
       quedaría intacta, lo que evita perder info única por error.

  Verificado manualmente en psql: 169 filas cumplen (1)+(2); 32 de esas
  además cumplen (3) y son las que esta migración borra.

  ## Idempotencia

  La sentencia es idempotente: una segunda ejecución afecta a 0 filas
  porque las huérfanas con `qn = name` para `(file_id, name)` donde ya
  existe hermano prefijado dejan de existir tras la primera corrida.

  ## Reversibilidad

  `down/0` devuelve `:ok` — no conservamos las filas borradas y no hay
  forma fiable de reconstruirlas sin re-indexar el repo. Si necesitas
  recuperarlas, restaura el dump físico de la BD anterior a esta
  migración.
  """

  # Idempotente: borrar de nuevo tras el primer éxito es no-op (no quedan
  # huérfanas con `qn = name` que tengan hermano prefijado). Solo borra
  # filas `s1` (huérfanas del pre-fix NIF) confirmadas por la existencia
  # de un hermano `s2` con prefijo de módulo en el mismo file.
  def up do
    execute("""
    DELETE FROM symbols s1
    USING projects p
    WHERE p.id = s1.project_id
      AND s1.qualified_name = s1.name
      AND s1.kind IN ('function', 'macro', 'type', 'callback', 'behaviour', 'use')
      AND EXISTS (
        SELECT 1 FROM symbols s2
        WHERE s2.file_id = s1.file_id
          AND s2.name = s1.name
          AND s2.qualified_name != s1.qualified_name
          AND s2.qualified_name LIKE ('%.' || s1.name)
      )
    """)
  end

  def down, do: :ok
end
