#!/bin/bash
# inject_req_queue.sh — Inject FUSE Request Queue Block (Branch B)
# Starts a FUSE daemon with high latency causing queue buildup
# Usage: bash inject_req_queue.sh [mount_point] [delay_ms]

MOUNT_POINT="${1:-/tmp/fuse_slow_test}"
DELAY_MS="${2:-2000}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
DAEMON_BIN="$SRC_DIR/bin/fuse_slow_daemon"
PID_FILE="/tmp/fuse_slow_daemon.pid"

echo "[Inject] FUSE Request Queue Block (Branch B)"
echo "  Mount point: $MOUNT_POINT"
echo "  Delay per op: ${DELAY_MS}ms"

# Build if needed
if [ ! -f "$DAEMON_BIN" ]; then
    echo "  Building slow daemon..."
    make -C "$SRC_DIR" 2>&1 | tail -5
fi

# Start daemon (if not already running)
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "  Daemon already running (PID: $(cat $PID_FILE))"
else
    mkdir -p "$MOUNT_POINT"
    $DAEMON_BIN -f "$MOUNT_POINT" -o delay_ms=$DELAY_MS &
    DAEMON_PID=$!
    echo $DAEMON_PID > "$PID_FILE"
    sleep 3
    echo "  Daemon started (PID: $DAEMON_PID)"
fi

# Verify mount
echo "  Verifying mount..."
ls -la "$MOUNT_POINT" > /dev/null 2>&1
echo "  ls exit code: $? (0=ok, but expected to be slow)"

# Start concurrent operations to build queue
echo "  Generating concurrent requests to build queue..."
for i in $(seq 1 20); do
    (dd if=/dev/zero of="$MOUNT_POINT/test_file_$i" bs=4K count=10 2>/dev/null) &
done
echo "  Background requests submitted (each takes ${DELAY_MS}ms)"

# Check waiting
sleep 2
echo ""
echo "  Current waiting values:"
for conn in /sys/fs/fuse/connections/*/; do
    w=$(cat "$conn/waiting" 2>/dev/null)
    echo "    waiting=$w"
done

echo ""
echo "[Inject] Done — FUSE ops are slow, queue buildup expected"
echo "  To adjust delay: echo 'delay=100' > $MOUNT_POINT/ctl_delay"
echo "  To stop: kill $(cat $PID_FILE 2>/dev/null) && fusermount -u $MOUNT_POINT"
