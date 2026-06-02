#!/usr/bin/env bash
# =============================================================================
# Script: diagnose_io_uring_workers.sh
# Purpose: Diagnose io-wq worker and SQPOLL thread evidence.
# Usage: bash diagnose_io_uring_workers.sh [-p pid] [-l log_file]
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

section "io_uring Worker and SQPOLL Diagnosis"
echo "pid=${PID:-none}"
echo "log_file=${LOG_FILE:-none}"
echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

section "1. Global io_uring worker threads"
ps -eLo pid,tid,ppid,psr,stat,pcpu,comm,wchan:32,args 2>/dev/null \
  | awk 'NR == 1 || /iou-wrk|iou-sqp|io_uring|io_wq/' \
  | head -200 || true

section "2. Target process threads"
if [ -n "$PID" ]; then
  ps -L -p "$PID" -o pid,tid,psr,stat,pcpu,pmem,comm,wchan:32 2>/dev/null || true
  echo
  echo "--- target thread states sample ---"
  for task in /proc/"$PID"/task/*; do
    [ -d "$task" ] || continue
    tid=${task##*/}
    printf '== tid=%s ==\n' "$tid"
    grep -E 'Name|State|voluntary|nonvoluntary|Cpus_allowed_list' "$task/status" 2>/dev/null || true
    printf 'wchan='
    cat "$task/wchan" 2>/dev/null || true
    echo
  done | head -500
  echo
  echo "--- process cgroup ---"
  cat "/proc/$PID/cgroup" 2>/dev/null || true
else
  echo "No -p PID provided; target process thread evidence is unavailable."
fi

section "3. SQPOLL and worker log signals"
if [ -n "$LOG_FILE" ]; then
  grep -Ein 'SQPOLL|sqpoll|iou-sqp|iou-wrk|io-wq|worker|blocked|D state|timeout|affinity|cpuset|cgroup|scheduler|EAGAIN|EPERM|EINVAL' "$LOG_FILE" | tail -160 || true
else
  echo "No -l log file provided."
fi

section "4. CPU and scheduler hints"
{
  echo "--- loadavg ---"
  cat /proc/loadavg 2>/dev/null || true
  echo
  echo "--- cpu quota files under cgroup v2 root when available ---"
  [ -r /sys/fs/cgroup/cpu.max ] && cat /sys/fs/cgroup/cpu.max || true
  [ -r /sys/fs/cgroup/io.stat ] && head -50 /sys/fs/cgroup/io.stat || true
} 2>/dev/null

section "5. Interpretation"
cat <<'EOF'
Worker starvation or blockage is likely when:
- many iou-wrk threads are in D state or the same wchan
- completion delay correlates with blocked filesystem/block I/O
- cgroup CPU or I/O limits constrain the target workload

SQPOLL-specific issues are likely when:
- setup used IORING_SETUP_SQPOLL and returned EPERM/EINVAL
- iou-sqp threads are pinned to constrained CPUs or consume unexpected CPU
- submit path depends on SQPOLL but the polling thread is not scheduled

Do not conclude worker exhaustion from thread count alone. Correlate worker
state, application symptoms, backend latency, and completion behavior.
EOF
