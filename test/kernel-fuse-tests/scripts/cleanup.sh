#!/bin/bash
# cleanup.sh — Universal cleanup for FUSE test environments
# Usage: sudo bash cleanup.sh

echo "[Cleanup] FUSE test environment cleanup..."

# Kill any FUSE test daemons
echo "  Killing test daemons..."
for pname in fuse_test_daemon fuse_crash_daemon fuse_slow_daemon fuse_mt_deadlock_daemon; do
    pkill -f "$pname" 2>/dev/null && echo "  Killed $pname"
done

# Unmount test mount points
echo "  Unmounting test mount points..."
for mp in /tmp/fuse_test /tmp/fuse_test_mount /tmp/fuse_slow_test /tmp/fuse_deadlock_test; do
    mountpoint -q "$mp" 2>/dev/null
    if [ $? -eq 0 ]; then
        fusermount -u "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
        echo "  Unmounted $mp"
    fi
    rmdir "$mp" 2>/dev/null || true
done

# Restore /dev/fuse permissions if changed
if [ -c /dev/fuse ]; then
    current_perm=$(stat -c '%a' /dev/fuse 2>/dev/null)
    if [ "$current_perm" != "666" ]; then
        chmod 666 /dev/fuse 2>/dev/null && echo "  Restored /dev/fuse permissions to 666"
    fi
fi

# Remove temporary files
echo "  Cleaning temp files..."
rm -rf /tmp/fuse_test_* 2>/dev/null
rm -rf /tmp/fuse_mixed_report 2>/dev/null

echo "[Cleanup] Done"
