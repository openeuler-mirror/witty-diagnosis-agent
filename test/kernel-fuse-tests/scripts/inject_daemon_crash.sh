#!/bin/bash
# inject_daemon_crash.sh — Inject FUSE Daemon Crash (Branch A)
# Starts a test FUSE daemon, then crashes it via SIGKILL
# Usage: bash inject_daemon_crash.sh [mount_point] [kill_method]
#   kill_method: sigkill (default), sigsegv, abort, exit

MOUNT_POINT="${1:-/tmp/fuse_test}"
KILL_METHOD="${2:-sigkill}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
DAEMON_BIN="$SRC_DIR/bin/fuse_crash_daemon"
PID_FILE="/tmp/fuse_crash_daemon.pid"

echo "[Inject] FUSE Daemon Crash (Branch A)"
echo "  Mount point: $MOUNT_POINT"
echo "  Kill method: $KILL_METHOD"

# Switch based on method
case "$KILL_METHOD" in
    sigsegv|abort|exit|fuse_exit)
        # Use crash daemon with control file
        echo "  Using controlled crash daemon..."

        # Check if already running
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "  Daemon already running (PID: $(cat $PID_FILE))"
        else
            mkdir -p "$MOUNT_POINT"
            if [ ! -f "$DAEMON_BIN" ]; then
                echo "  Building crash daemon..."
                make -C "$SRC_DIR" 2>&1 | tail -5
            fi
            $DAEMON_BIN -f "$MOUNT_POINT" &
            DAEMON_PID=$!
            echo $DAEMON_PID > "$PID_FILE"
            sleep 2
            echo "  Daemon started (PID: $DAEMON_PID)"
        fi

        # Verify FUSE works before crash
        echo "  Verifying FUSE mount..."
        ls -la "$MOUNT_POINT" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "  FUSE mount operational"
        else
            echo "  WARNING: FUSE mount not responding"
        fi

        # Trigger crash
        echo "  Triggering crash ($KILL_METHOD)..."
        echo "$KILL_METHOD" > "$MOUNT_POINT/ctl_crash"
        sleep 1

        # Verify EIO
        echo "  Verifying EIO..."
        stat "$MOUNT_POINT" > /dev/null 2>&1
        echo "  stat exit code: $? (expect non-zero with EIO)"
        ;;
    *)
        # Use simple SIGKILL
        echo "  Using SIGKILL method..."

        # Start test daemon
        TEST_DAEMON="$SRC_DIR/bin/fuse_test_daemon"
        if [ ! -f "$TEST_DAEMON" ]; then
            echo "  Building test daemon..."
            make -C "$SRC_DIR" 2>&1 | tail -5
        fi

        mkdir -p "$MOUNT_POINT"
        $TEST_DAEMON -f "$MOUNT_POINT" &
        DAEMON_PID=$!
        echo $DAEMON_PID > "$PID_FILE"
        sleep 2
        echo "  Daemon started (PID: $DAEMON_PID)"

        # Verify
        ls -la "$MOUNT_POINT" > /dev/null 2>&1
        echo "  FUSE mount: $? (0=ok)"

        # Kill daemon
        echo "  Killing daemon (SIGKILL)..."
        kill -9 $DAEMON_PID 2>/dev/null
        sleep 1
        rm -f "$PID_FILE"

        # Verify EIO
        echo "  Verifying EIO..."
        stat "$MOUNT_POINT" > /dev/null 2>&1
        echo "  stat exit code: $?"
        ;;
esac

echo "[Inject] Done — FUSE daemon crashed, EIO expected on mount point access"
