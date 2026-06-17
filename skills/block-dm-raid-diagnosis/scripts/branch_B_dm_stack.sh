#!/bin/bash
# Branch B: Device-Mapper Mapping Stack Analysis
# Use when: dmsetup table shows errors, DM missing devices, thin pool/cache issues
# Usage: bash branch_B_dm_stack.sh [dm_device]
set -e
DEV="${1:-}"
TIMEOUT="timeout 5"

echo "=========================================="
echo " Branch B: Device-Mapper Stack Analysis"
[ -n "$DEV" ] && echo " Device: $DEV"
echo "=========================================="

# 1. DM device topology
echo ""
echo "--- 1. DM device tree ---"
$TIMEOUT dmsetup ls --tree 2>/dev/null || echo "N/A"

echo ""
echo "--- 2. DM dependency tree ---"
$TIMEOUT dmsetup deps 2>/dev/null || echo "N/A"

# 3. DM table (mapping targets)
echo ""
echo "--- 3. DM table ---"
if [ -n "$DEV" ]; then
    $TIMEOUT dmsetup table "$DEV" 2>/dev/null || echo "Device $DEV not found"
else
    $TIMEOUT dmsetup table 2>/dev/null || echo "N/A"
fi
echo "--- Target types ---"
$TIMEOUT dmsetup table 2>/dev/null | awk '{print $3}' | sort -u || echo "N/A"

# 4. DM status
echo ""
echo "--- 4. DM status ---"
if [ -n "$DEV" ]; then
    $TIMEOUT dmsetup status "$DEV" 2>/dev/null || echo "N/A"
else
    $TIMEOUT dmsetup status 2>/dev/null || echo "N/A"
fi

# 5. Thin pool analysis
echo ""
echo "--- 5. Thin pool check ---"
$TIMEOUT dmsetup table 2>/dev/null | grep -i thin || echo "(no thin pools)"
echo "--- Thin pool status ---"
$TIMEOUT dmsetup status 2>/dev/null | grep -i thin || echo "(none)"
echo "--- Thin pool kernel warnings ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "dm-thin" | tail -10 || echo "(none)"

# 6. Cache analysis
echo ""
echo "--- 6. DM cache check ---"
$TIMEOUT dmsetup table 2>/dev/null | grep -i cache || echo "(no cache targets)"
echo "--- Cache status ---"
$TIMEOUT dmsetup status 2>/dev/null | grep -i cache | head -5 || echo "(none)"

# 7. Crypt analysis
echo ""
echo "--- 7. DM crypt check ---"
$TIMEOUT dmsetup table 2>/dev/null | grep -i crypt || echo "(no crypt targets)"

# 8. Suspended devices
echo ""
echo "--- 8. Suspended devices ---"
$TIMEOUT dmsetup info -c -o suspended 2>/dev/null | grep -v "suspended$" || echo "N/A"

# 9. DM kernel error messages
echo ""
echo "--- 9. DM kernel errors ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "device-mapper" | tail -15 || echo "N/A"

echo ""
echo "=========================================="
echo " Branch B analysis complete."
echo "=========================================="
