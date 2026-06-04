#!/bin/bash
# Inject: TCP Fallback Failure (Branch G)
# Blocks TCP DNS while leaving UDP DNS operational
# Usage: bash inject_tcp_fallback.sh [duration_seconds]

DURATION=${1:-300}
PID_FILE="/tmp/dns_tcp_block_inject.pid"

echo "[Inject] TCP Fallback Failure - Blocking TCP DNS for ${DURATION}s"

python3 "$(dirname "$0")/../src/dns_tcp_block.py" "$DURATION" &
echo $! > "$PID_FILE"

echo "[Inject] PID: $(cat $PID_FILE)"
echo "[Inject] UDP DNS still works, but TCP fallback will fail"
echo "[Inject] dig +tcp and large DNS responses will timeout"
echo "[Inject] Run cleanup.sh or wait ${DURATION}s to restore"
