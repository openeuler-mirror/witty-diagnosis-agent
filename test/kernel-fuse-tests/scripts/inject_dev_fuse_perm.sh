#!/bin/bash
# inject_dev_fuse_perm.sh — Inject /dev/fuse Permission Problem (Branch F)
# Restricts /dev/fuse to root-only, causing non-root daemon launch failures
# Usage: bash inject_dev_fuse_perm.sh [mode] [owner]
#   mode: 0600 (default), 0640
#   owner: root:root (default)
#   After test: run cleanup.sh to restore

MODE="${1:-0600}"
OWNER="${2:-root:root}"

echo "[Inject] /dev/fuse Permission Problem (Branch F)"
echo "  Current: $(stat -c '%a %U:%G' /dev/fuse 2>/dev/null)"
echo "  Target:  $MODE $OWNER"

# Save original
ORIG_PERM=$(stat -c '%a' /dev/fuse 2>/dev/null)
ORIG_OWNER=$(stat -c '%U:%G' /dev/fuse 2>/dev/null)
echo "$ORIG_PERM:$ORIG_OWNER" > /tmp/fuse_dev_perm_backup.txt

# Change permissions
chmod "$MODE" /dev/fuse 2>/dev/null
chown "$OWNER" /dev/fuse 2>/dev/null

echo "  New: $(stat -c '%a %U:%G' /dev/fuse 2>/dev/null)"
echo ""
echo "  Now try launching a FUSE daemon as non-root:"
echo "    $ src/bin/fuse_test_daemon -f /tmp/fuse_test"
echo "  (Expected: permission denied)"
echo ""
echo "  Restore: chmod $ORIG_PERM /dev/fuse; chown $ORIG_OWNER /dev/fuse"
echo "  Or run: bash scripts/cleanup.sh"
