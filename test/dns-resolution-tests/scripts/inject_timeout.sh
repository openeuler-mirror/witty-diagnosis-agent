#!/bin/bash
# Inject: DNS Timeout (Branch A)
# Blocks all DNS traffic via iptables to simulate server unreachable
# Usage: bash inject_timeout.sh [duration_seconds]

DURATION=${1:-300}
PID_FILE="/tmp/dns_timeout_inject.pid"

echo "[Inject] DNS Timeout - Blocking port 53 for ${DURATION}s"

# Run Python injector in background
python3 "$(dirname "$0")/../src/dns_timeout_inject.py" "$DURATION" &
echo $! > "$PID_FILE"

echo "[Inject] PID: $(cat $PID_FILE)"
echo "[Inject] dig/nslookup will now timeout"
echo "[Inject] Run cleanup.sh or wait ${DURATION}s to restore"
