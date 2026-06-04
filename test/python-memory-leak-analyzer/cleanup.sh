#!/usr/bin/env bash
# Clean python-memory-leak-analyzer test outputs.

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT_DIR="$ROOT_DIR/out"
STRESS_LOG="$ROOT_DIR/out-stress-run.log"

rm -rf "$OUT_DIR"
rm -f "$STRESS_LOG"
find "$ROOT_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} +
echo "cleaned $OUT_DIR"
