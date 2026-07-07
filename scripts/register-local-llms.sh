#!/usr/bin/env bash
# =============================================================================
# register-local-llms.sh — Registra los LLMs locales (gpt-oss + qwen3-embed)
#                          en la configuración de Delfos.
#
# Lee los parámetros de ~/bin/llama-run (HOST, PORT, EMBED_PORT, API_KEY)
# y los escribe en ~/.config/delfos/config.json como los endpoints
# `embedding` (Qwen3-Embedding-8B en :9998) y `llm` (gpt-oss-20b en :9999).
#
# Uso:
#   bin/register-local-llms.sh              # registra y prueba
#   bin/register-local-llms.sh --no-test    # solo escribe, sin probar
#   bin/register-local-llms.sh --probe     # solo prueba, no escribe
#
# Pre-requisito: tener `llama-run` en el PATH (o ~/bin/) con las funciones
# `embed` y `gpt_oss` definidas.
# =============================================================================

set -euo pipefail

# ─── CONFIGURACIÓN (debe coincidir con llama-run) ───────────────────────────
HOST="${HOST:-127.0.0.1}"
EMBED_PORT="${EMBED_PORT:-9998}"
LLM_PORT="${LLM_PORT:-9999}"
API_KEY="${API_KEY:-sk-local-dev-key}"
EMBED_MODEL="${EMBED_MODEL:-embed}"      # alias en llama-server
LLM_MODEL="${LLM_MODEL:-gpt-oss}"        # alias en llama-server

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/delfos"
CONFIG_FILE="$CONFIG_DIR/config.json"

# ─── BANNER ─────────────────────────────────────────────────────────────────
cat <<'BANNER'

  Delfos — Registro de LLMs locales
  =================================
  Embedding  →  http://127.0.0.1:9998  (Qwen3-Embedding-8B, 1024-d)
  Chat       →  http://127.0.0.1:9999  (gpt-oss-20b)

BANNER

# ─── FLAGS ──────────────────────────────────────────────────────────────────
DO_WRITE=1
DO_TEST=1
for arg in "$@"; do
    case "$arg" in
        --no-test) DO_TEST=0 ;;
        --no-write) DO_WRITE=0 ;;
        --probe)    DO_WRITE=0; DO_TEST=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

# ─── HELPERS ────────────────────────────────────────────────────────────────

probe_endpoint() {
    local url="$1" name="$2"
    local model_path="/v1/models"

    printf "  %-12s " "$name"

    if curl -fsS --max-time 3 \
            -H "Authorization: Bearer $API_KEY" \
            "$url$model_path" >/dev/null 2>&1; then
        echo "✓ reachable ($url)"
        return 0
    else
        echo "✗ UNREACHABLE ($url)"
        echo "    Tip: lanzarlo con 'llama-run $name' en otra terminal."
        return 1
    fi
}

ensure_config_file() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        chmod 700 "$CONFIG_DIR"
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "  ! $CONFIG_FILE no existe — creando con defaults…"
        cat > "$CONFIG_FILE" <<EOF
{
  "analysis":  { "churn_max_commits": "1000" },
  "embedding": {},
  "indexing":  { "ignore_dirs": [], "max_chunk_tokens": "512" },
  "llm":       {},
  "retrieval": { "bm25_weight": "0.25", "final_k": "7", "graph_weight": "0.2", "top_k": "25", "vector_weight": "0.55" }
}
EOF
        chmod 600 "$CONFIG_FILE"
    fi
}

# Atomic JSON edit via python (jq is not always installed; python3 is).
# We rewrite the whole file but keep all other sections intact.
update_json() {
    local file="$1"
    local emb_url="$2" emb_model="$3" emb_dim="$4"
    local llm_url="$5" llm_model="$6"

    python3 - <<PY
import json, sys

path = "$file"
with open(path) as f:
    cfg = json.load(f)

# Schema-driven cleanup: drop any keys not in the canonical schema.
# This removes stale fields like 'gguf_path', 'port', 'api-key' (hyphen)
# or 'embedding' (stray in llm section) that earlier wizard versions left
# behind.
EMBEDDING_KEYS = {"provider", "url", "model", "api_key", "dim",
                  "batch_size", "timeout_ms"}
LLM_KEYS = {"provider", "url", "model", "api_key", "timeout_ms",
            "summarize_max_tokens", "explain_max_tokens",
            "query_max_tokens", "thinker_url", "thinker_model",
            "use_thinker_for_query"}

cfg.setdefault("embedding", {})
for k in list(cfg["embedding"]):
    if k not in EMBEDDING_KEYS:
        del cfg["embedding"][k]
cfg["embedding"].update({
    "provider":   "local",
    "url":        "$emb_url",
    "model":      "$emb_model",
    "dim":        "$emb_dim",
    "batch_size": "48",
    "timeout_ms": "25000",
    "api_key":    "$API_KEY",
})

cfg.setdefault("llm", {})
for k in list(cfg["llm"]):
    if k not in LLM_KEYS:
        del cfg["llm"][k]
cfg["llm"].update({
    "provider":   "local",
    "url":        "$llm_url",
    "model":      "$llm_model",
    "api_key":    "$API_KEY",
    "summarize_max_tokens": "180",
    "explain_max_tokens":   "600",
    "query_max_tokens":     "512",
    "timeout_ms": "45000",
    "thinker_url": "http://$HOST:8081",
    "thinker_model": "thinker",
    "use_thinker_for_query": "false",
})

with open(path, "w") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

# ─── WRITE ──────────────────────────────────────────────────────────────────
if [[ "$DO_WRITE" -eq 1 ]]; then
    ensure_config_file

    EMBED_URL="http://$HOST:$EMBED_PORT"
    LLM_URL="http://$HOST:$LLM_PORT"
    # Qwen3-Embedding-8B outputs 4096 dims by default but llama.cpp
    # can be configured to truncate; we use 1024 to keep storage sane.
    EMBED_DIM="${EMBED_DIM:-1024}"

    echo "→ Escribiendo $CONFIG_FILE…"
    update_json "$CONFIG_FILE" "$EMBED_URL" "$EMBED_MODEL" "$EMBED_DIM" "$LLM_URL" "$LLM_MODEL"
    chmod 600 "$CONFIG_FILE"
    echo "  ✓ escrito."
    echo
fi

# ─── TEST ───────────────────────────────────────────────────────────────────
if [[ "$DO_TEST" -eq 1 ]]; then
    echo "→ Probando endpoints…"
    probe_endpoint "http://$HOST:$EMBED_PORT" "embedding" || true
    probe_endpoint "http://$HOST:$LLM_PORT"    "llm" || true
    echo
fi

# ─── DONE ───────────────────────────────────────────────────────────────────
cat <<EOF
Listo. Para verificar desde delfos:
  delfos doctor           # 8 checks, ambos providers deben pasar
  delfos config models     # modelos activos
  delfos config show       # config completa

Para arrancar los servidores en sendas terminales:
  llama-run embed                  # embedding en :9998
  llama-run gpt_oss medium          # chat en :9999

Si la URL/puerto no coinciden con tu llama-run, sobreescribe:
  API_KEY=sk-xxx EMBED_PORT=9000 LLM_PORT=9001 $0
EOF