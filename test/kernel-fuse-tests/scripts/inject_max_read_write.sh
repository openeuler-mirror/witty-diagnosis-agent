#!/bin/bash
# inject_max_read_write.sh — Inject max_read/max_write misconfig (Branch C)
# Starts FUSE daemon with artificially small max_read to cause poor read perf
# Usage: bash inject_max_read_write.sh [mount_point] [max_read]

MOUNT_POINT="${1:-/tmp/fuse_test_mount}"
MAX_READ="${2:-4096}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
DAEMON_BIN="$SRC_DIR/bin/fuse_test_daemon"
PID_FILE="/tmp/fuse_test_mount.pid"

echo "[Inject] FUSE max_read/max_write Misconfig (Branch C)"
echo "  Mount point: $MOUNT_POINT"
echo "  max_read: $MAX_READ (expected degraded perf)"

# Build
if [ ! -f "$DAEMON_BIN" ]; then
    echo "  Building test daemon..."
    make -C "$SRC_DIR" 2>&1 | tail -5
fi

mkdir -p "$MOUNT_POINT"

# Mount with small max_read
$DAEMON_BIN -f "$MOUNT_POINT" -o max_read=$MAX_READ &
DAEMON_PID=$!
echo $DAEMON_PID > "$PID_FILE"
sleep 2

echo "  Daemon PID: $DAEMON_PID"
echo ""
echo "  Verifying max_read:"
for conn in /sys/fs/fuse/connections/*/; do
    mr=$(cat "$conn/max_read" 2>/dev/null)
    echo "    max_read = $mr"
done

echo ""
echo "  Run performance test:"
echo "    dd if=$MOUNT_POINT of=/dev/null bs=1M count=100"
echo "    # Expected: very slow due to 4K max_read"
echo ""
echo "  To stop: kill $DAEMON_PID && fusermount -u $MOUNT_POINT"
