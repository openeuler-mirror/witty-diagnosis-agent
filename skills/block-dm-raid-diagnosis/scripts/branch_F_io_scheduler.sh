#!/bin/bash
# Branch F: IO Scheduler & Tuning Analysis
# Use when: latency spikes, throughput lower than expected, IO scheduler misconfiguration
# Usage: bash branch_F_io_scheduler.sh [device]
set -e
DEV="${1:-}"
TIMEOUT="timeout 5"

echo "=========================================="
echo " Branch F: IO Scheduler & Tuning Analysis"
[ -n "$DEV" ] && echo " Device: $DEV"
echo "=========================================="

# 1. Active schedulers
echo ""
echo "--- 1. Available & active schedulers ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ -n "$DEV" ] && [ "$name" != "$DEV" ] && continue
    echo "=== $name ==="
    [ -f "$dev/queue/scheduler" ] && echo "  scheduler: $(cat "$dev/queue/scheduler" 2>/dev/null)"
    [ -f "$dev/queue/nr_requests" ] && echo "  nr_requests: $(cat "$dev/queue/nr_requests" 2>/dev/null)"
    [ -f "$dev/queue/read_ahead_kb" ] && echo "  read_ahead_kb: $(cat "$dev/queue/read_ahead_kb" 2>/dev/null)"
    [ -f "$dev/queue/max_sectors_kb" ] && echo "  max_sectors_kb: $(cat "$dev/queue/max_sectors_kb" 2>/dev/null)"
    [ -f "$dev/queue/nomerges" ] && echo "  nomerges: $(cat "$dev/queue/nomerges" 2>/dev/null)"
    [ -f "$dev/queue/rq_affinity" ] && echo "  rq_affinity: $(cat "$dev/queue/rq_affinity" 2>/dev/null)"
    [ -f "$dev/queue/rotational" ] && echo "  rotational: $(cat "$dev/queue/rotational" 2>/dev/null)"
done

# 2. IO block layer statistics
echo ""
echo "--- 2. IO stats per device ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ -n "$DEV" ] && [ "$name" != "$DEV" ] && continue
    [ -f "$dev/stat" ] || continue
    read rd r_mrg rd_sec rd_tic wr wr_mrg wr_sec wr_tic inflight io_tic io_whip discard d_sec d_tic d_ios < "$dev/stat" 2>/dev/null
    echo ""
    echo "=== $name ==="
    echo "  Reads completed: $rd"
    echo "  Reads merged: $r_mrg"
    echo "  Read sectors: $rd_sec"
    echo "  Read time (ms): $rd_tic"
    echo "  Writes completed: $wr"
    echo "  Writes merged: $wr_mrg"
    echo "  Write sectors: $wr_sec"
    echo "  Write time (ms): $wr_tic"
    echo "  IOs in flight: $inflight"
    echo "  Total IO time (ms): $io_tic"
    echo "  Weighted IO time: $io_whip"
    # Average latency helpers
    [ "$rd" -gt 0 ] && avg_rd="$(echo "scale=2; $rd_tic / $rd" | bc 2>/dev/null)" || avg_rd="N/A"
    [ "$wr" -gt 0 ] && avg_wr="$(echo "scale=2; $wr_tic / $wr" | bc 2>/dev/null)" || avg_wr="N/A"
    echo "  Avg read latency: ${avg_rd}ms"
    echo "  Avg write latency: ${avg_wr}ms"
done

# 3. WBT (write-back throttling)
echo ""
echo "--- 3. WBT settings ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ -n "$DEV" ] && [ "$name" != "$DEV" ] && continue
    [ -f "$dev/queue/wbt_lat_usec" ] && echo "$name wbt_lat_usec: $(cat "$dev/queue/wbt_lat_usec" 2>/dev/null)"
    [ -f "$dev/queue/wb_lat_usec" ] && echo "$name wb_lat_usec: $(cat "$dev/queue/wb_lat_usec" 2>/dev/null)"
done

# 4. IO priority & control group
echo ""
echo "--- 4. IO priority & cgroup ---"
echo "ionice: $(ionice 2>/dev/null || echo 'N/A')"
echo "--- CFQ/bfq io priority (if applicable) ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ -n "$DEV" ] && [ "$name" != "$DEV" ] && continue
    [ -d "$dev/queue/iosched" ] && echo "=== $name iosched ===" && ls "$dev/queue/iosched/" 2>/dev/null | head -5
done

# 5. Device mapper IO stats
echo ""
echo "--- 5. DM stacked IO stats ---"
$TIMEOUT dmsetup status 2>/dev/null || echo "N/A"

echo ""
echo "=========================================="
echo " Branch F analysis complete."
echo "=========================================="
