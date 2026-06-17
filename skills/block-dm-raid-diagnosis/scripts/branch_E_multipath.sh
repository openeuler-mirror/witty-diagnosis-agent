#!/bin/bash
# Branch E: Multipath Analysis
# Use when: multipath -ll shows failed/ghost paths, active paths showing errors
# Usage: bash branch_E_multipath.sh
set -e
TIMEOUT="timeout 8"

echo "=========================================="
echo " Branch E: Multipath Analysis"
echo "=========================================="

# 1. Multipath topology
echo ""
echo "--- 1. Multipath topology ---"
$TIMEOUT multipath -ll 2>/dev/null || echo "N/A"
echo "--- Short view ---"
$TIMEOUT multipath -l 2>/dev/null || echo "N/A"

# 2. Multipathd daemon status
echo ""
echo "--- 2. Multipathd status ---"
systemctl status multipathd 2>/dev/null || service multipathd status 2>/dev/null || echo "multipathd service status unavailable"
echo "--- Multipathd maps ---"
$TIMEOUT multipathd show maps 2>/dev/null || echo "N/A"

# 3. Path group distribution
echo ""
echo "--- 3. Paths detailed ---"
$TIMEOUT multipathd show paths 2>/dev/null | head -50 || echo "N/A"
echo "--- Path failures count ---"
$TIMEOUT multipathd show paths 2>/dev/null | grep -c "fail" 2>/dev/null || echo "(no failures)"

# 4. Fail and recovery history
echo ""
echo "--- 4. Fail/Recovery status ---"
$TIMEOUT multipathd show status 2>/dev/null || echo "N/A"
echo "--- Daemon log (recent) ---"
journalctl -u multipathd --no-pager -n 20 2>/dev/null || echo "N/A"

# 5. Configuration
echo ""
echo "--- 5. Multipath configuration ---"
cat /etc/multipath.conf 2>/dev/null || echo "No multipath.conf (using defaults)"
cat /etc/multipath/bindings 2>/dev/null | head -20 || echo "No bindings file"

# 6. DM table for multipath devices
echo ""
echo "--- 6. DM multipath table ---"
$TIMEOUT dmsetup table 2>/dev/null | grep -i multipath || echo "(no multipath DM entries)"

# 7. Per-path IO statistics
echo ""
echo "--- 7. Per-path IO stats ---"
for dev in /sys/block/sd*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ -d "/sys/block/$name/device" ] || continue
    # Check if it's part of multipath
    holders=$(ls "$dev/holders" 2>/dev/null)
    [ -z "$holders" ] && continue
    echo "=== $name holders: $holders ==="
    read rd r_mrg rd_sec rd_tic wr wr_mrg wr_sec wr_tic inflight io_tic io_whip discard etc < "$dev/stat" 2>/dev/null
    echo "  rd=$rd wr=$wr inflight=$inflight io_tic=$io_tic"
done

# 8. Kernel multipath errors
echo ""
echo "--- 8. Kernel multipath errors ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "multipath" | tail -10 || echo "N/A"

echo ""
echo "=========================================="
echo " Branch E analysis complete."
echo "=========================================="
