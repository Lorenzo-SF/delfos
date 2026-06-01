#!/usr/bin/env bash
# Delfos LLM Server launcher
# Uso: MODEL_ID=embed PORT=9998 bash llm-server.sh
#      MODEL_ID=phi4  PORT=8080 bash llm-server.sh
#
# MODELOS RECOMENDADOS:
#
# Embeddings — BGE-M3 Q4_K_M (~1.1 GB VRAM)
#   Descargar: https://huggingface.co/groonga/bge-m3-Q4_K_M-GGUF/blob/main/bge-m3-q4_k_m.gguf
#
# LLM — Phi-4-mini-instruct Q4_K_M (~2.8 GB VRAM)
#   Descargar: https://huggingface.co/bartowski/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf
#
# Total VRAM: ~3.9 GB — entra en cualquier GPU de 6+ GB
# (alternativa más ligera: Qwen2.5-Coder-1.5B ~1.1 GB → total ~2.2 GB)
#
# Alternativas al Phi-4-mini si prefieres más enfoque en código:
#   Qwen2.5-Coder-3B Q4_K_M (~2.2 GB) — mejor para código, peor en prose
#   Qwen2.5-Coder-1.5B Q4_K_M (~1.1 GB) — mínimo absoluto, calidad aceptable

set -euo pipefail

MODEL_ID="${MODEL_ID:-phi4}"
PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"
MODELS_DIR="${MODELS_DIR:-$HOME/models/gguf}"

LLAMA_BIN=$(command -v llama-server 2>/dev/null || echo "")
if [ -z "$LLAMA_BIN" ]; then
  echo "ERROR: llama-server no encontrado en PATH."
  echo "Instala llama.cpp: https://github.com/ggerganov/llama.cpp/releases"
  exit 1
fi

case "$MODEL_ID" in
  embed|bge-m3|embedding)
    MODEL_FILE="${MODELS_DIR}/bge-m3-q4_k_m.gguf"
    if [ ! -f "$MODEL_FILE" ]; then
      echo "Modelo no encontrado: $MODEL_FILE"
      echo "Descargar: https://huggingface.co/groonga/bge-m3-Q4_K_M-GGUF/blob/main/bge-m3-q4_k_m.gguf"
      exit 1
    fi
    echo "Arrancando embedding server BGE-M3 en ${HOST}:${PORT}..."
    exec "$LLAMA_BIN" \
      -m "$MODEL_FILE" \
      --port "$PORT" \
      --host "$HOST" \
      --embedding \
      --threads 4 \
      --batch-size 64 \
      --ctx-size 2048 \
      --mlock \
      --no-mmap \
      --flash-attn
    ;;

  phi4|phi-4-mini)
    MODEL_FILE="${MODELS_DIR}/Phi-4-mini-instruct-Q4_K_M.gguf"
    if [ ! -f "$MODEL_FILE" ]; then
      echo "Modelo no encontrado: $MODEL_FILE"
      echo "Descargar: https://huggingface.co/bartowski/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf"
      exit 1
    fi
    echo "Arrancando LLM Phi-4-mini en ${HOST}:${PORT}..."
    exec "$LLAMA_BIN" \
      -m "$MODEL_FILE" \
      --port "$PORT" \
      --host "$HOST" \
      --threads 6 \
      --batch-size 128 \
      --ctx-size 8192 \
      --mlock \
      --no-mmap \
      --flash-attn
    ;;

  qwen-3b|qwen2.5-coder-3b)
    MODEL_FILE="${MODELS_DIR}/qwen2.5-coder-3b-instruct-q4_k_m.gguf"
    if [ ! -f "$MODEL_FILE" ]; then
      echo "Modelo no encontrado: $MODEL_FILE"
      echo "Descargar: https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf"
      exit 1
    fi
    echo "Arrancando LLM Qwen2.5-Coder-3B en ${HOST}:${PORT}..."
    exec "$LLAMA_BIN" \
      -m "$MODEL_FILE" \
      --port "$PORT" \
      --host "$HOST" \
      --threads 6 \
      --batch-size 128 \
      --ctx-size 8192 \
      --mlock \
      --no-mmap \
      --flash-attn
    ;;

  qwen-1.5b|qwen2.5-coder-1.5b)
    MODEL_FILE="${MODELS_DIR}/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
    if [ ! -f "$MODEL_FILE" ]; then
      echo "Modelo no encontrado: $MODEL_FILE"
      echo "Descargar: https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
      exit 1
    fi
    echo "Arrancando LLM Qwen2.5-Coder-1.5B en ${HOST}:${PORT} (~1.1 GB VRAM)..."
    exec "$LLAMA_BIN" \
      -m "$MODEL_FILE" \
      --port "$PORT" \
      --host "$HOST" \
      --threads 4 \
      --batch-size 64 \
      --ctx-size 4096 \
      --mlock \
      --no-mmap \
      --flash-attn
    ;;

  *)
    echo "MODEL_ID desconocido: $MODEL_ID"
    echo "Valores válidos: embed, phi4, qwen-3b, qwen-1.5b"
    echo ""
    echo "Ejemplos:"
    echo "  MODEL_ID=embed PORT=9998 bash llm-server.sh"
    echo "  MODEL_ID=phi4  PORT=8080 bash llm-server.sh"
    exit 1
    ;;
esac
