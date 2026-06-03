#!/usr/bin/env bash
# =============================================================================
# Script: diagnose_io_uring_limits.sh
# Purpose: Diagnose resource-limit evidence for io_uring setup/register failures.
# Usage: bash diagnose_io_uring_limits.sh [-p pid] [-l log_file]
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

print_limits() {
  if [ -n "$PID" ]; then
    echo "Source: /proc/$PID/limits"
    cat "/proc/$PID/limits" 2>/dev/null || echo "limits not readable"
  else
    echo "Source: current shell ulimit"
    ulimit -a 2>/dev/null || true
  fi
}

extract_limit_value() {
  local name="$1"
  local file="$2"
  awk -v n="$name" '$0 ~ n {print $4, $5; exit}' "$file" 2>/dev/null
}

section "io_uring Resource Limit Diagnosis"
echo "pid=${PID:-none}"
echo "log_file=${LOG_FILE:-none}"
echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

section "1. Limits"
print_limits

section "2. Memory and cgroup"
grep -E 'MemTotal|MemAvailable|Mlocked|Unevictable|SwapTotal|SwapFree' /proc/meminfo 2>/dev/null || true
if [ -n "$PID" ]; then
  echo
  echo "--- /proc/$PID/status memory fields ---"
  grep -E 'VmSize|VmRSS|VmData|VmLck|Threads|FDSize|CapEff|CapPrm' "/proc/$PID/status" 2>/dev/null || true
  echo
  echo "--- /proc/$PID/cgroup ---"
  cat "/proc/$PID/cgroup" 2>/dev/null || true
fi

section "3. io_uring errors from logs"
if [ -n "$LOG_FILE" ]; then
  grep -Ein 'io_uring(_setup|_enter|_register)?|ENOMEM|EPERM|EAGAIN|EINVAL|EBUSY|EFAULT|memlock|locked memory|fixed buffer|registered buffer|register.*buffer' "$LOG_FILE" | tail -120 || true
  echo
  echo "--- resource limit hints from log ---"
  grep -Ein 'ulimit -l|Max locked memory|registered_buffer_bytes|buffer_bytes|Cannot allocate memory' "$LOG_FILE" | tail -80 || true
else
  echo "No -l log file provided; use application logs or strace output for syscall errno evidence."
fi

section "4. Interpretation"
LOG_MEMLOCK=""
LOG_REGISTERED_BYTES=""
LOG_REGISTER_ENOMEM="no"
if [ -n "$LOG_FILE" ]; then
  LOG_MEMLOCK=$(sed -n 's/.*ulimit -l=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -1)
  LOG_REGISTERED_BYTES=$(sed -n 's/.*registered_buffer_bytes=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -1)
  if grep -Eiq 'io_uring_register.*errno=12|io_uring_register.*ENOMEM|Cannot allocate memory' "$LOG_FILE"; then
    LOG_REGISTER_ENOMEM="yes"
  fi
fi

if [ -n "$LOG_MEMLOCK" ] && [ -n "$LOG_REGISTERED_BYTES" ] && [ "$LOG_REGISTER_ENOMEM" = "yes" ]; then
  LOG_MEMLOCK_BYTES=$((LOG_MEMLOCK * 1024))
  echo "Log-derived memlock limit: ${LOG_MEMLOCK} KB (${LOG_MEMLOCK_BYTES} bytes)"
  echo "Log-derived registered buffer bytes: ${LOG_REGISTERED_BYTES}"
  if [ "$LOG_REGISTERED_BYTES" -gt "$LOG_MEMLOCK_BYTES" ] 2>/dev/null; then
    echo "Conclusion hint: fixed buffer registration is constrained by RLIMIT_MEMLOCK evidence in the log."
  else
    echo "Conclusion hint: io_uring_register ENOMEM is present, but registered bytes do not exceed the parsed memlock limit."
  fi
  echo
fi

if [ -n "$PID" ] && [ -r "/proc/$PID/limits" ]; then
  MEMLOCK=$(extract_limit_value "Max locked memory" "/proc/$PID/limits")
  NOFILE=$(extract_limit_value "Max open files" "/proc/$PID/limits")
  NPROC=$(extract_limit_value "Max processes" "/proc/$PID/limits")
  echo "Max locked memory: ${MEMLOCK:-unknown}"
  echo "Max open files: ${NOFILE:-unknown}"
  echo "Max processes: ${NPROC:-unknown}"
  if echo "$MEMLOCK" | grep -Eiq '^[0-9]+ bytes$|^[0-9]+ kbytes$'; then
    echo "Signal: finite memlock limit detected; fixed buffer registration may fail if registered bytes exceed this limit."
  elif echo "$MEMLOCK" | grep -Eiq 'unlimited'; then
    echo "Signal: memlock is unlimited; fixed-buffer ENOMEM is more likely memory pressure, invalid mapping, or cgroup accounting."
  else
    echo "Signal: memlock could not be classified; compare with requested fixed buffer size."
  fi
else
  echo "No process limits available; classify resource-limit root cause only if logs show errno and requested ring/buffer size."
fi

cat <<'EOF'

Required evidence before high-confidence conclusion:
- syscall name and errno: io_uring_setup/io_uring_register/io_uring_enter
- requested ring entries or registered buffer bytes
- Max locked memory and process/cgroup memory state
- whether the same workload succeeds after changing only the limit in a test environment
EOF
