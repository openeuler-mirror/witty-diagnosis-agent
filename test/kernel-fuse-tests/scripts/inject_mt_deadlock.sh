#!/bin/bash
# inject_mt_deadlock.sh — Inject FUSE Multi-thread Deadlock (Branch E)
# Starts a FUSE daemon with intentional lock inversion
# Usage: bash inject_mt_deadlock.sh [mount_point]

MOUNT_POINT="${1:-/tmp/fuse_deadlock_test}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
DAEMON_BIN="$SRC_DIR/bin/fuse_mt_deadlock_daemon"
PID_FILE="/tmp/fuse_mt_deadlock.pid"

echo "[Inject] FUSE Multi-thread Deadlock (Branch E)"
echo "  Mount point: $MOUNT_POINT"

# Build if needed
if [ ! -f "$DAEMON_BIN" ]; then
    echo "  Building deadlock daemon..."
    make -C "$SRC_DIR" 2>&1 | tail -5
fi

# Start daemon
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "  Daemon already running (PID: $(cat $PID_FILE))"
else
    mkdir -p "$MOUNT_POINT"
    $DAEMON_BIN -f "$MOUNT_POINT" &
    DAEMON_PID=$!
    echo $DAEMON_PID > "$PID_FILE"
    sleep 3
    echo "  Daemon started (PID: $DAEMON_PID)"
fi

# Verify mount
echo "  Verifying mount..."
ls -la "$MOUNT_POINT" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  FUSE mount operational"
else
    echo "  WARNING: FUSE mount not responding"
fi

# Trigger deadlock
echo "  Triggering deadlock..."
echo "deadlock" > "$MOUNT_POINT/ctl_deadlock"
sleep 2

# Verify hang
echo "  Verifying hang (timeout 5s)..."
timeout 5 ls -la "$MOUNT_POINT" > /dev/null 2>&1
EXIT_CODE=$?
echo "  ls exit code: $EXIT_CODE (expect 124 for timeout)"

echo ""
echo "[Inject] Done — FUSE daemon should be in deadlock state"
echo "  Check thread stacks: for tid in /proc/$(cat $PID_FILE)/task/*/; do"
echo "    echo \"TID \$(basename \$tid):\"; cat \$tid/stack 2>/dev/null; done"
