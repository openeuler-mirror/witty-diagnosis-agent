#!/bin/bash
# Branch A: Block Layer IO Analysis
# Use when: %util=100%, await>50ms, D-state process accumulation
# Usage: bash branch_A_block_layer.sh [device]
set -e
DEV="${1:-all}"
TIMEOUT="timeout 5"

echo "=========================================="
echo " Branch A: Block Layer IO Analysis"
echo " Device: $DEV"
echo "=========================================="

# 1. IO performance deep dive
echo ""
echo "--- 1. iostat extended (5 samples) ---"
$TIMEOUT iostat -x 1 5 2>/dev/null || echo "iostat not available"

# 2. In-flight IO
echo ""
echo "--- 2. In-flight I/O per device ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ "$DEV" != "all" ] && [ "$name" != "$DEV" ] && continue
    [ -f "$dev/inflight" ] && echo "$name: $(cat "$dev/inflight" 2>/dev/null)"
done

# 3. Queue state
echo ""
echo "--- 3. Queue state ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ "$DEV" != "all" ] && [ "$name" != "$DEV" ] && continue
    echo "=== $name ==="
    for f in scheduler nr_requests read_ahead_kb max_sectors_kb rotational rq_affinity \
             wbt_lat_usec nomerges write_cache max_segments; do
        [ -f "$dev/queue/$f" ] && echo "  $f: $(cat "$dev/queue/$f" 2>/dev/null)"
    done
    # Check if queue is frozen
    [ -f "$dev/queue/freeze_count" ] && echo "  freeze_count: $(cat "$dev/queue/freeze_count" 2>/dev/null)"
    # Read-only?
    [ -f "$dev/ro" ] && echo "  ro: $(cat "$dev/ro" 2>/dev/null)"
done

# 4. IO error counters
echo ""
echo "--- 4. IO error counters ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ "$DEV" != "all" ] && [ "$name" != "$DEV" ] && continue
    read rd r_mrg rd_sec rd_tic wr wr_mrg wr_sec wr_tic inflight io_tic io_whip discard etc < "$dev/stat" 2>/dev/null
    echo "$name: rd=$rd wr=$wr inflight=$inflight io_tic=$io_tic"
done

# 5. D-state process stack traces
echo ""
echo "--- 5. D-state process stacks ---"
for pid in $(ps aux 2>/dev/null | grep ' D' | grep -v grep | awk '{print $2}'); do
    echo "=== PID $pid ==="
    cat /proc/$pid/stack 2>/dev/null || echo "(stack unavailable)"
    cat /proc/$pid/comm 2>/dev/null | tr '\0' ' ' || echo "(comm unavailable)"
    echo "---"
done 2>/dev/null || echo "(no D-state or access denied)"

# 6. Kernel IO error detail
echo ""
echo "--- 6. Kernel IO errors (detailed) ---"
$TIMEOUT dmesg 2>/dev/null | grep -E -i "I/O error|Buffer I/O|blk_update_request|end_request|hung_task|blocked for more" | tail -20 || echo "N/A"

echo ""
echo "=========================================="
echo " Branch A analysis complete."
echo "=========================================="
