#!/bin/bash
# setup.sh — Setup FUSE test environment
# Usage: sudo bash setup.sh

echo "[Setup] FUSE test environment setup..."

# 1. Check FUSE kernel module
echo "  Checking FUSE kernel module..."
if ! lsmod | grep -q "^fuse"; then
    echo "  Loading FUSE module..."
    modprobe fuse
    if [ $? -ne 0 ]; then
        echo "  ERROR: Cannot load FUSE module!"
        echo "  Ensure CONFIG_FUSE_FS is enabled in kernel."
        exit 1
    fi
fi
echo "  FUSE module loaded: $(lsmod | grep "^fuse" | awk '{print $1, $2, $3}')"

# 2. Check /dev/fuse
echo "  Checking /dev/fuse..."
if [ ! -c /dev/fuse ]; then
    echo "  Creating /dev/fuse (mknod)..."
    mknod -m 666 /dev/fuse c 10 229 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "  ERROR: Cannot create /dev/fuse!"
        exit 1
    fi
fi
echo "  /dev/fuse: $(stat -c '%A %U:%G' /dev/fuse 2>/dev/null)"

# 3. Install dependencies (best-effort)
echo "  Checking dependencies..."
for cmd in gcc pkg-config strace lsof dd; do
    if command -v $cmd &>/dev/null; then
        echo "    $cmd: ✓"
    else
        echo "    $cmd: ✗ (not found)"
    fi
done

# 4. Build test daemons
echo "  Building test daemons..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
cd "$SRC_DIR"
make 2>&1 | sed 's/^/    /'
if [ $? -ne 0 ]; then
    echo "  WARNING: Build failed. Some tests may not work."
    echo "  Install libfuse-dev/fuse-devel package."
fi

# 5. Create test mount points
echo "  Creating test mount points..."
for mp in /tmp/fuse_test /tmp/fuse_test_mount /tmp/fuse_slow_test /tmp/fuse_deadlock_test; do
    mkdir -p "$mp"
done

echo ""
echo "[Setup] Complete."
echo "  Test daemon binaries: $SRC_DIR/bin/"
echo "  Mount points: /tmp/fuse_test, /tmp/fuse_slow_test, /tmp/fuse_deadlock_test"
echo ""
echo "  Quick test:"
echo "    cd $SRC_DIR"
echo "    sudo ./bin/fuse_test_daemon -f /tmp/fuse_test &"
echo "    sleep 2 && ls -la /tmp/fuse_test"
echo "    echo 'hello' > /tmp/fuse_test/test.txt && cat /tmp/fuse_test/test.txt"
echo "    fusermount -u /tmp/fuse_test && kill %1"
