#!/usr/bin/env bash
# =============================================================================
# Script: collect_io_uring_context.sh
# Purpose: Collect read-only baseline context for io_uring diagnosis.
# Usage: bash collect_io_uring_context.sh [-p pid] [-l log_file] [-o output_dir]
# =============================================================================

set -u

PID=""
LOG_FILE=""
OUT_DIR="/tmp/io_uring_diag_$(date +%Y%m%d_%H%M%S)"

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

if [ -n "$PID" ] && ! [ "$PID" -eq "$PID" ] 2>/dev/null; then
  echo "ERROR: -p must be a numeric PID" >&2
  exit 2
fi

if [ -n "$PID" ] && [ ! -d "/proc/$PID" ]; then
  echo "ERROR: /proc/$PID does not exist; provide a running PID or omit -p for system-level collection" >&2
  exit 3
fi

if [ -n "$LOG_FILE" ] && [ ! -r "$LOG_FILE" ]; then
  echo "ERROR: log file is not readable: $LOG_FILE" >&2
  exit 3
fi

mkdir -p "$OUT_DIR" || {
  echo "ERROR: cannot create output directory: $OUT_DIR" >&2
  exit 4
}

run_cmd() {
  local title="$1"
  shift
  echo "===== $title ====="
  echo "COMMAND: $*"
  "$@" 2>&1 || echo "COMMAND_FAILED: $*"
  echo
}

copy_if_readable() {
  local source="$1"
  local dest="$2"
  if [ -r "$source" ]; then
    cp "$source" "$dest" 2>/dev/null || true
  else
    echo "NOT_READABLE: $source" > "$dest"
  fi
}

{
  echo "io_uring diagnosis baseline"
  echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "host=$(hostname 2>/dev/null || echo unknown)"
  echo "pid=${PID:-none}"
  echo "log_file=${LOG_FILE:-none}"
  echo "output_dir=$OUT_DIR"
  echo
  run_cmd "kernel" uname -a
  [ -r /etc/os-release ] && run_cmd "os-release" cat /etc/os-release
  run_cmd "architecture" uname -m
  run_cmd "ulimit" sh -c 'ulimit -a'
  run_cmd "memory" sh -c "grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree|Mlocked|Unevictable' /proc/meminfo"
  run_cmd "io_uring headers" sh -c "grep -R 'IORING_\\(FEAT\\|SETUP\\|OP\\)_' /usr/include/linux/io_uring.h 2>/dev/null | head -120 || echo 'io_uring header not found'"
} > "$OUT_DIR/system_context.txt"

{
  echo "io_uring related kernel logs"
  if command -v journalctl >/dev/null 2>&1; then
    echo "===== journalctl -k ====="
    journalctl -k --no-pager 2>/dev/null | grep -Ei 'io_uring|uring|iou-wrk|iou-sqp|O_DIRECT|direct I/O|EINVAL|ENOMEM|EAGAIN|ENOSYS' | tail -200 || true
    echo
  fi
  echo "===== dmesg ====="
  dmesg -T 2>/dev/null | grep -Ei 'io_uring|uring|iou-wrk|iou-sqp|O_DIRECT|direct I/O|EINVAL|ENOMEM|EAGAIN|ENOSYS' | tail -200 || true
} > "$OUT_DIR/kernel_io_uring_logs.txt"

if [ -n "$PID" ]; then
  mkdir -p "$OUT_DIR/proc_$PID"
  copy_if_readable "/proc/$PID/status" "$OUT_DIR/proc_$PID/status.txt"
  copy_if_readable "/proc/$PID/limits" "$OUT_DIR/proc_$PID/limits.txt"
  copy_if_readable "/proc/$PID/cgroup" "$OUT_DIR/proc_$PID/cgroup.txt"
  copy_if_readable "/proc/$PID/maps" "$OUT_DIR/proc_$PID/maps.txt"

  {
    run_cmd "process command" sh -c "tr '\\0' ' ' < /proc/$PID/cmdline; echo"
    run_cmd "process stat" ps -p "$PID" -o pid,ppid,stat,pcpu,pmem,etime,comm,args
    run_cmd "threads" ps -L -p "$PID" -o pid,tid,psr,stat,pcpu,pmem,comm,wchan:32
    run_cmd "fd sample" sh -c "ls -la /proc/$PID/fd 2>/dev/null | head -100"
    run_cmd "task states sample" sh -c "for t in /proc/$PID/task/*; do echo ==\$t==; grep -E 'Name|State|voluntary|nonvoluntary' \$t/status 2>/dev/null; cat \$t/wchan 2>/dev/null; echo; done | head -500"
  } > "$OUT_DIR/proc_$PID/process_runtime.txt"
fi

if [ -n "$LOG_FILE" ]; then
  {
    echo "io_uring patterns from $LOG_FILE"
    grep -Ein 'io_uring|uring|iou-wrk|iou-sqp|O_DIRECT|direct I/O|EINVAL|ENOMEM|EAGAIN|ENOSYS|CQ|SQ|completion|submit|fixed|buffer' "$LOG_FILE" | tail -300 || true
  } > "$OUT_DIR/input_log_matches.txt"
fi

cat > "$OUT_DIR/README.txt" <<EOF
io_uring diagnosis context was collected in read-only mode.

Key files:
- system_context.txt
- kernel_io_uring_logs.txt
- input_log_matches.txt (only when -l is provided)
- proc_${PID:-none}/ (only when -p is provided)

Next branch scripts:
- diagnose_io_uring_limits.sh
- diagnose_io_uring_rings.sh
- diagnose_io_uring_workers.sh
- diagnose_io_uring_compat.sh
EOF

echo "io_uring context collection complete"
echo "output_dir=$OUT_DIR"
