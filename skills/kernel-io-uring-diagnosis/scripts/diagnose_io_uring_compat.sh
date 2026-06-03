#!/usr/bin/env bash
# =============================================================================
# Script: diagnose_io_uring_compat.sh
# Purpose: Diagnose io_uring feature and kernel compatibility evidence.
# Usage: bash diagnose_io_uring_compat.sh [-l log_file]
# =============================================================================

set -u

LOG_FILE=""

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts ":l:h-:" opt; do
  case "$opt" in
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

section "io_uring Kernel Compatibility Diagnosis"
echo "log_file=${LOG_FILE:-none}"
echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

section "1. Runtime kernel"
uname -a 2>/dev/null || true
echo
[ -r /etc/os-release ] && cat /etc/os-release

section "2. Header feature symbols"
if [ -r /usr/include/linux/io_uring.h ]; then
  echo "--- IORING_SETUP flags ---"
  grep -E 'IORING_SETUP_' /usr/include/linux/io_uring.h | head -80 || true
  echo
  echo "--- IORING_FEAT bits ---"
  grep -E 'IORING_FEAT_' /usr/include/linux/io_uring.h | head -80 || true
  echo
  echo "--- Recent operation names from headers ---"
  grep -E 'IORING_OP_' /usr/include/linux/io_uring.h | tail -80 || true
else
  echo "/usr/include/linux/io_uring.h not found. Header evidence unavailable."
fi

section "3. Failure signals from logs"
if [ -n "$LOG_FILE" ]; then
  grep -Ein 'io_uring_setup|io_uring_register|io_uring_enter|IORING_|ENOSYS|EINVAL|EPERM|unsupported|invalid|feature|opcode|register' "$LOG_FILE" | tail -180 || true
else
  echo "No -l log file provided. Provide strace or application feature-probe output for stronger compatibility evidence."
fi

section "4. Runtime probing guidance"
cat <<'EOF'
Compatibility conclusions require runtime evidence.

High-confidence signals:
- io_uring_setup returns ENOSYS: syscall unavailable on this kernel.
- setup/register returns EINVAL and decoded flags/opcodes are unsupported by
  the running kernel.
- application feature probe reports a missing feature on the affected host and
  succeeds on a newer known-good kernel.

Medium-confidence signals:
- application was built with newer headers than the runtime kernel.
- same workload fails only on older distro kernel and succeeds on newer kernel.

Low-confidence signals:
- header symbol is missing or present without syscall errno evidence.
- only generic EINVAL is available and setup/register arguments are unknown.
EOF

section "5. Data to request"
cat <<'EOF'
- strace line for io_uring_setup/register/enter with errno
- setup flags, entries, and returned features
- register opcode and argument size
- liburing version or application io_uring wrapper version
- exact running kernel and distro release
EOF
