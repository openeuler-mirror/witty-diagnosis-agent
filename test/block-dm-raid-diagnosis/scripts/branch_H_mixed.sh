#!/bin/bash
# Branch H: Mixed / Complex Fault Analysis
# Use when: multiple layers involved, cross-stack root causes, cascading failures
# Usage: bash branch_H_mixed.sh
set -e
TIMEOUT="timeout 8"

echo "=========================================="
echo " Branch H: Mixed / Complex Fault Analysis"
echo "=========================================="

echo ""
echo "=== Phase 1: Cross-Layer Dependency Map ==="

# 1. Build dependency tree from bottom (sdX) to top (mount point)
echo ""
echo "--- 1. Bottom-up device dependency ---"
$TIMEOUT lsblk -s -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,PKNAME 2>/dev/null || echo "N/A"

# 2. Reverse dependency (invert tree)
echo ""
echo "--- 2. Top-down holders ---"
for dev in /sys/block/sd*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    holders=$(ls "$dev/holders" 2>/dev/null)
    [ -z "$holders" ] && continue
    echo "$name -> holders: $holders"
    # Check if holder has further holders
    for h in $holders; do
        h_holders=$(ls "/sys/block/$h/holders" 2>/dev/null)
        [ -n "$h_holders" ] && echo "  $h -> $h_holders"
    done
done

echo ""
echo "=== Phase 2: Cross-Layer Event Timeline ==="

# 3. Kernel messages across all relevant layers
echo ""
echo "--- 3. Block layer errors ---"
$TIMEOUT dmesg 2>/dev/null | grep -E "blk_update_request|I/O error|Buffer I/O|end_request" | tail -15 || echo "N/A"
echo "--- DM errors ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "device-mapper" | tail -10 || echo "N/A"
echo "--- md errors ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "md:" | tail -10 || echo "N/A"
echo "--- SCSI/ATA errors ---"
$TIMEOUT dmesg 2>/dev/null | grep -E "SCSI.*error|ata.*error|sd.*error" | tail -10 || echo "N/A"

echo ""
echo "=== Phase 3: Resource Contention Assessment ==="

# 4. Overall IO pressure
echo ""
echo "--- 4. IO pressure (psutil-like) ---"
$TIMEOUT iostat -x 1 3 2>/dev/null || echo "iostat not available"

# 5. D-state analysis
echo ""
echo "--- 5. D-state processes ---"
d_cnt=$(ps aux 2>/dev/null | grep ' D' | grep -v grep | wc -l)
echo "D-state count: $d_cnt"
ps aux 2>/dev/null | grep ' D' | grep -v grep | head -20 || echo "(none)"

# 6. IO wait / load
echo ""
echo "--- 6. CPU IO wait ---"
$TIMEOUT top -b -n 1 2>/dev/null | head -5 || echo "N/A"
$TIMEOUT vmstat 1 3 2>/dev/null || echo "N/A"

echo ""
echo "=== Phase 4: Integrity & Consistency Check ==="

# 7. Filesystem check signals
echo ""
echo "--- 7. FS read-only / errors ---"
$TIMEOUT dmesg 2>/dev/null | grep -E "EXT.*error|XFS.*error|EXT.*remount|XFS.*remount|journal|corrupt" | tail -10 || echo "N/A"

# 8. Disk SMART health (if smartctl exists)
echo ""
echo "--- 8. SMART health overview ---"
if command -v smartctl &>/dev/null; then
    for disk in /dev/sd[a-z]; do
        [ -b "$disk" ] || continue
        echo "=== $disk ==="
        $TIMEOUT smartctl -H "$disk" 2>/dev/null | grep -E "SMART|Status|health" | head -5 || echo "smartctl error"
    done
else
    echo "smartctl not available"
fi

echo ""
echo "=========================================="
echo " Branch H analysis complete."
echo "=========================================="
