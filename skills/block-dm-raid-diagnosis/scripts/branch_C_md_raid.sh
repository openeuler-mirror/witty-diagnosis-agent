#!/bin/bash
# Branch C: md Soft RAID Analysis
# Use when: /proc/mdstat shows degraded array [U_] or missing devices
# Usage: bash branch_C_md_raid.sh [md_device]
set -e
DEV="${1:-}"
TIMEOUT="timeout 5"

echo "=========================================="
echo " Branch C: md Soft RAID Analysis"
[ -n "$DEV" ] && echo " Device: $DEV"
echo "=========================================="

# 1. Overall status
echo ""
echo "--- 1. /proc/mdstat ---"
cat /proc/mdstat 2>/dev/null || echo "N/A"

# 2. Per-array detail
echo ""
echo "--- 2. mdadm detail ---"
if [ -n "$DEV" ]; then
    $TIMEOUT mdadm --detail "$DEV" 2>/dev/null || echo "Device $DEV not found or mdadm not available"
else
    for md in /dev/md[0-9]*; do
        [ -b "$md" ] || continue
        echo "=== $md ==="
        $TIMEOUT mdadm --detail "$md" 2>/dev/null || echo "mdadm error"
    done
fi

# 3. Component device examination
echo ""
echo "--- 3. Component device superblocks ---"
if [ -n "$DEV" ]; then
    # Get component devices from mdadm detail
    components=$($TIMEOUT mdadm --detail "$DEV" 2>/dev/null | grep -oP '/dev/[sv]d[a-z]+[0-9]*' || true)
    for comp in $components; do
        echo "=== $comp ==="
        $TIMEOUT mdadm --examine "$comp" 2>/dev/null | grep -E "Event|State|Role|Array|Device" | head -10 || echo "examine error"
    done
else
    # Examine all potential component devices
    for disk in /dev/sd[a-z]*[0-9]; do
        [ -b "$disk" ] || continue
        result=$($TIMEOUT mdadm --examine "$disk" 2>/dev/null) || continue
        echo "=== $disk ==="
        echo "$result" | grep -E "Event|State|Role|Array|Device|Version" | head -10
    done
fi

# 4. mismatch_cnt
echo ""
echo "--- 4. mismatch_cnt ---"
for md in /sys/block/md[0-9]*; do
    [ -d "$md" ] || continue
    name=$(basename "$md")
    [ -n "$DEV" ] && [ "$name" != "$(basename "$DEV")" ] && continue
    echo "$name mismatch_cnt: $(cat "$md/md/mismatch_cnt" 2>/dev/null || echo 'N/A')"
    echo "$name sync_action: $(cat "$md/md/sync_action" 2>/dev/null || echo 'N/A')"
    [ -f "$md/md/sync_completed" ] && echo "$name sync_completed: $(cat "$md/md/sync_completed" 2>/dev/null)"
    [ -f "$md/md/raid_disks" ] && echo "$name raid_disks: $(cat "$md/md/raid_disks" 2>/dev/null)"
    [ -f "$md/md/degraded" ] && echo "$name degraded: $(cat "$md/md/degraded" 2>/dev/null)"
done

# 5. Rebuild speed limits
echo ""
echo "--- 5. Rebuild speed limits ---"
echo "speed_limit_min: $(cat /proc/sys/dev/raid/speed_limit_min 2>/dev/null || echo 'N/A')"
echo "speed_limit_max: $(cat /proc/sys/dev/raid/speed_limit_max 2>/dev/null || echo 'N/A')"

# 6. md kernel messages
echo ""
echo "--- 6. md kernel messages ---"
$TIMEOUT dmesg 2>/dev/null | grep -i "md:" | tail -20 || echo "N/A"
$TIMEOUT dmesg 2>/dev/null | grep -i "raid" | tail -10 || echo "N/A"

# 7. md sysfs additional stats
echo ""
echo "--- 7. md sysfs additional ---"
for md in /sys/block/md[0-9]*; do
    [ -d "$md" ] || continue
    name=$(basename "$md")
    [ -n "$DEV" ] && [ "$name" != "$(basename "$DEV")" ] && continue
    for attr in array_size chunk_size layout level metadata_version raid_disks stride_size; do
        [ -f "$md/md/$attr" ] && echo "$name $attr: $(cat "$md/md/$attr" 2>/dev/null)"
    done
    # Disk status
    for rd in $md/md/rd[0-9]*; do
        [ -d "$rd" ] || continue
        rname=$(basename "$rd")
        [ -f "$rd/block" ] && block=$(readlink "$rd/block" 2>/dev/null) || block="?"
        [ -f "$rd/state" ] && state=$(cat "$rd/state" 2>/dev/null) || state="?"
        echo "$name $rname: block=$block state=$state"
    done
done

echo ""
echo "=========================================="
echo " Branch C analysis complete."
echo "=========================================="
