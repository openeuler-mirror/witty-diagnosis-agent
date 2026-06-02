#!/usr/bin/env bash
# =============================================================================
# kernel-io-uring-diagnosis test runner
# Usage:
#   ./run.sh build
#   ./run.sh run <baseline|memlock|ring|sqpoll|odirect|compat|all>
#   ./run.sh status
#   ./run.sh clean
# =============================================================================

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT_DIR="$ROOT_DIR/out"
BIN="$OUT_DIR/io_uring_fault_probe"
SRC="$ROOT_DIR/fault-injection/src/io_uring_fault_probe.c"

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

build_probe() {
  mkdir -p "$OUT_DIR"
  if ! command -v gcc >/dev/null 2>&1; then
    echo "ERROR: gcc is required" >&2
    exit 3
  fi
  gcc -Wall -Wextra -O2 "$SRC" -o "$BIN"
  echo "built $BIN"
}

run_one() {
  local scenario="$1"
  mkdir -p "$OUT_DIR"
  [ -x "$BIN" ] || build_probe
  local log="$OUT_DIR/${scenario}.log"
  echo "running scenario=$scenario"
  echo "log=$log"
  case "$scenario" in
    baseline)
      (cd "$ROOT_DIR" && "$BIN" baseline) 2>&1 | tee "$log"
      ;;
    memlock)
      (
        cd "$ROOT_DIR" || exit 1
        ulimit -l 64 2>/dev/null || true
        echo "ulimit -l=$(ulimit -l 2>/dev/null || echo unknown)"
        "$BIN" memlock
      ) 2>&1 | tee "$log"
      ;;
    ring|sqpoll|odirect|compat)
      (cd "$ROOT_DIR" && "$BIN" "$scenario") 2>&1 | tee "$log"
      ;;
    all)
      for s in baseline memlock ring sqpoll odirect compat; do
        run_one "$s"
      done
      ;;
    *)
      echo "ERROR: unknown scenario: $scenario" >&2
      usage
      exit 2
      ;;
  esac
}

status_tests() {
  echo "out_dir=$OUT_DIR"
  if [ -d "$OUT_DIR" ]; then
    find "$OUT_DIR" -maxdepth 1 -type f -printf '%f %s bytes\n' 2>/dev/null || ls -la "$OUT_DIR"
  else
    echo "no output directory"
  fi
}

clean_tests() {
  rm -rf "$OUT_DIR"
  echo "cleaned $OUT_DIR"
}

case "${1:-}" in
  build)
    build_probe
    ;;
  run)
    run_one "${2:-baseline}"
    ;;
  status)
    status_tests
    ;;
  clean)
    clean_tests
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "ERROR: unknown command: $1" >&2
    usage
    exit 2
    ;;
esac
