#!/usr/bin/env bash
# =============================================================================
# Script: diagnose_io_uring_rings.sh
# Purpose: Diagnose SQ/CQ pressure, completion delay, and O_DIRECT evidence.
# Usage: bash diagnose_io_uring_rings.sh [-p pid] [-l log_file]
# =============================================================================

set -u

PID=""
LOG_FILE=""

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts ":p:l:h-:" opt; do
  case "$opt" in
    p) PID="$OPTARG" ;;
    l) LOG_FILE="$OPTARG" ;;
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
  echo "ERROR: /proc/$PID does not exist" >&2
  exit 3
fi

if [ -n "$LOG_FILE" ] && [ ! -r "$LOG_FILE" ]; then
  echo "ERROR: log file is not readable: $LOG_FILE" >&2
  exit 3
fi

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

section "io_uring Ring and Completion Diagnosis"
echo "pid=${PID:-none}"
echo "log_file=${LOG_FILE:-none}"
echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

section "1. Application or strace log signals"
if [ -n "$LOG_FILE" ]; then
  grep -Ein 'SQ|submission|submit|queue full|CQ|completion|CQE|overflow|dropped|timeout|latency|io_uring_enter|EAGAIN|EBUSY|EINVAL|O_DIRECT|direct I/O|short (read|write)|unalign|alignment' "$LOG_FILE" | tail -160 || true
else
  echo "No -l log file provided. Provide application logs or strace output to classify SQ/CQ pressure."
fi

section "2. Process thread and fd hints"
if [ -n "$PID" ]; then
  ps -L -p "$PID" -o pid,tid,psr,stat,pcpu,pmem,comm,wchan:32 2>/dev/null || true
  echo
  echo "--- fd sample ---"
  ls -la "/proc/$PID/fd" 2>/dev/null | head -80 || true
  echo
  echo "--- maps sample for anonymous/direct buffers ---"
  grep -Ei 'anon|memfd|huge|rw' "/proc/$PID/maps" 2>/dev/null | head -80 || true
else
  echo "No -p PID provided; process-level CQ consumer and fd evidence is unavailable."
fi

section "3. Kernel log hints"
{
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -k --no-pager 2>/dev/null | grep -Ei 'io_uring|uring|O_DIRECT|direct I/O|CQ.*overflow|SQ.*overflow|queue.*overflow|io_uring.*timeout|io_uring.*EINVAL|io_uring.*EAGAIN' | tail -120 || true
  fi
  dmesg -T 2>/dev/null | grep -Ei 'io_uring|uring|O_DIRECT|direct I/O|CQ.*overflow|SQ.*overflow|queue.*overflow|io_uring.*timeout|io_uring.*EINVAL|io_uring.*EAGAIN' | tail -120 || true
} | awk 'NF && !seen[$0]++'

section "4. O_DIRECT alignment checks to request"
cat <<'EOF'
If O_DIRECT is involved, collect:
- file path and mount: findmnt -T <file>
- filesystem block size: stat -fc 'fs=%T block_size=%s' <path>
- device logical/physical block size: blockdev --getss/--getpbsz <device>
- application buffer address, length, and file offset

Direct I/O EINVAL requires checking buffer address, I/O length, file offset,
filesystem constraints, and backing device constraints.
EOF

section "5. Interpretation"
cat <<'EOF'
Classify as ring-capacity only when evidence shows queue pressure:
- SQ full, CQ overflow, missing CQE, or repeated EAGAIN/EBUSY around io_uring_enter
- submit rate exceeds completion consumption
- consumer thread is blocked, delayed, or absent

Classify as backend/worker delay when completions are late and workers are in
D state, blocked in filesystem/block I/O, or logs show storage latency.

Classify as direct-I/O-alignment when O_DIRECT EINVAL correlates with unaligned
buffer address, length, or file offset and the same operation works without
O_DIRECT.
EOF
