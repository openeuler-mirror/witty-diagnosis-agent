#!/bin/bash
# Inject: NXDOMAIN False Positive (Branch B)
# Starts a fake DNS server that returns NXDOMAIN for all queries
# Prerequisite: Resolve <skill-path>/src

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="/tmp/dns_nxdomain_inject.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "[Inject] NXDOMAIN injector already running (PID: $(cat $PID_FILE))"
    exit 1
fi

echo "[Inject] Starting NXDOMAIN fake DNS server..."

python3 "$SCRIPT_DIR/../src/dns_nxdomain_fake.py" &
echo $! > "$PID_FILE"
sleep 1

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "[Inject] NXDOMAIN injector started (PID: $(cat $PID_FILE))"
    echo "[Inject] All DNS queries will return NXDOMAIN"
    echo "[Inject] Ensure fake DNS is used as nameserver: nameserver 127.0.0.1"
else
    echo "[Inject] Failed to start (port 53 may be in use)"
    rm -f "$PID_FILE"
    exit 1
fi
