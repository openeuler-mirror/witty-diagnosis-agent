#!/usr/bin/env bash
# =============================================================================
# Script: diagnose_io_uring_all.sh
# Purpose: Run the io_uring read-only branch scripts into one output directory.
# Usage: bash diagnose_io_uring_all.sh [-p pid] [-l log_file] [-o output_dir]
# =============================================================================

set -u

PID=""
LOG_FILE=""
OUT_DIR="/tmp/io_uring_diag_all_$(date +%Y%m%d_%H%M%S)"

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts ":p:l:o:h-:" opt; do
  case "$opt" in
    p) PID="$OPTARG" ;;
    l) LOG_FILE="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    -)
      case "$OPTARG" in
        help) usage; exit 0 ;;
        *) echo "ERROR: unknown option --$OPTARG" >&2; usage; exit 2 ;;
      esac
      ;;
    :) echo "ERROR: -$OPTARG requires an argument" >&2; usage; exit 2 ;;
    *) echo "ERROR: unknown option -$OPTARG" >&2; usage; exit 2 ;;
  esac
done

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$OUT_DIR" || exit 4

ARGS=()
[ -n "$PID" ] && ARGS+=("-p" "$PID")
[ -n "$LOG_FILE" ] && ARGS+=("-l" "$LOG_FILE")

bash "$SCRIPT_DIR/collect_io_uring_context.sh" "${ARGS[@]}" -o "$OUT_DIR/context" > "$OUT_DIR/collect.log" 2>&1
bash "$SCRIPT_DIR/diagnose_io_uring_limits.sh" "${ARGS[@]}" > "$OUT_DIR/limits.txt" 2>&1
bash "$SCRIPT_DIR/diagnose_io_uring_rings.sh" "${ARGS[@]}" > "$OUT_DIR/rings.txt" 2>&1
bash "$SCRIPT_DIR/diagnose_io_uring_workers.sh" "${ARGS[@]}" > "$OUT_DIR/workers.txt" 2>&1
if [ -n "$LOG_FILE" ]; then
  bash "$SCRIPT_DIR/diagnose_io_uring_compat.sh" -l "$LOG_FILE" > "$OUT_DIR/compat.txt" 2>&1
else
  bash "$SCRIPT_DIR/diagnose_io_uring_compat.sh" > "$OUT_DIR/compat.txt" 2>&1
fi

echo "io_uring read-only diagnosis complete"
echo "output_dir=$OUT_DIR"
