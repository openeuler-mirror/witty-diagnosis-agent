#!/bin/bash
# block-dm-raid-diagnosis: Baseline collection script
# Collects comprehensive block device / DM / md / LVM / multipath state
# Usage: bash collect_blk_info.sh [output_dir]
set -e
OUTDIR="${1:-/tmp/blk_diag_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"
TIMEOUT="timeout 5"

echo "=========================================="
echo " BLK/RAID/LVM Diagnostic Collection"
echo " Output: $OUTDIR"
echo "=========================================="

# Section A: System Overview
echo ""
echo "=== Section A: System Overview ==="
echo "--- Kernel ---"
uname -a 2>/dev/null || echo "N/A"
echo "--- Memory ---"
$TIMEOUT free -h 2>/dev/null || echo "N/A"
echo "--- Mount ---"
$TIMEOUT mount 2>/dev/null | head -30 || echo "N/A"
echo "--- /etc/fstab (relevant) ---"
grep -E '^[^#]' /etc/fstab 2>/dev/null | head -20 || echo "N/A"

# Section B: Block Device Topology
echo ""
echo "=== Section B: Block Device Topology ==="
echo "--- lsblk ---"
$TIMEOUT lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,ROTA 2>/dev/null || echo "N/A"
echo "--- /proc/partitions ---"
cat /proc/partitions 2>/dev/null || echo "N/A"
echo "--- /dev/disk/by-* (symlinks) ---"
for d in /dev/disk/by-path /dev/disk/by-id /dev/disk/by-uuid /dev/disk/by-label; do
    [ -d "$d" ] && echo "$d:" && ls -la "$d" 2>/dev/null | head -20 && echo "..."
done

# Section C: IO Performance
echo ""
echo "=== Section C: IO Performance ==="
echo "--- iostat -x (5 samples) ---"
$TIMEOUT iostat -x 1 3 2>/dev/null || echo "iostat not available"
echo "--- /sys/block/*/stat ---"
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    read rd r_mrg rd_sec rd_tic wr wr_mrg wr_sec wr_tic inflight io_tic io_whip < "$dev/stat" 2>/dev/null && \
    echo "$name: rd=$rd wr=$wr inflight=$inflight io_tic=$io_tic"
done

# Section D: Block Device Queue Parameters
echo ""
echo "=== Section D: Queue Parameters ==="
for dev in /sys/block/[svdmn]d*; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    echo "--- $name ---"
    for param in scheduler nr_requests read_ahead_kb max_sectors_kb rotational \
                 rq_affinity wbt_lat_usec nomerges; do
        [ -f "$dev/queue/$param" ] && echo "  $param: $(cat "$dev/queue/$param" 2>/dev/null)"
    done
    [ -f "$dev/ro" ] && echo "  ro: $(cat "$dev/ro" 2>/dev/null)"
    [ -f "$dev/size" ] && echo "  size: $(cat "$dev/size" 2>/dev/null) sectors"
done

# Section E: Device-Mapper
echo ""
echo "=== Section E: Device-Mapper ==="
echo "--- dmsetup ls ---"
$TIMEOUT dmsetup ls 2>/dev/null || echo "N/A"
echo "--- dmsetup table ---"
$TIMEOUT dmsetup table 2>/dev/null || echo "N/A"
echo "--- dmsetup status ---"
$TIMEOUT dmsetup status 2>/dev/null || echo "N/A"
echo "--- dmsetup deps ---"
$TIMEOUT dmsetup deps 2>/dev/null || echo "N/A"
echo "--- dmsetup info ---"
$TIMEOUT dmsetup info -c 2>/dev/null | head -30 || echo "N/A"

# Section F: md RAID
echo ""
echo "=== Section F: md RAID ==="
echo "--- /proc/mdstat ---"
cat /proc/mdstat 2>/dev/null || echo "N/A"
echo "--- mdadm detail ---"
for md in /dev/md[0-9]*; do
    [ -b "$md" ] || continue
    echo "=== $md ==="
    $TIMEOUT mdadm --detail "$md" 2>/dev/null || echo "mdadm not available"
    md_name=$(basename "$md")
    [ -f "/sys/block/$md_name/md/mismatch_cnt" ] && \
        echo "mismatch_cnt: $(cat /sys/block/$md_name/md/mismatch_cnt 2>/dev/null)"
    [ -f "/sys/block/$md_name/md/sync_action" ] && \
        echo "sync_action: $(cat /sys/block/$md_name/md/sync_action 2>/dev/null)"
done

# Section G: LVM
echo ""
echo "=== Section G: LVM ==="
echo "--- pvs ---"
$TIMEOUT pvs 2>/dev/null || echo "N/A"
echo "--- pvs -a (include missing) ---"
$TIMEOUT pvs -a 2>/dev/null || echo "N/A"
echo "--- vgs ---"
$TIMEOUT vgs 2>/dev/null || echo "N/A"
echo "--- vgs -o+vg_missing_pv_count ---"
$TIMEOUT vgs -o +vg_missing_pv_count 2>/dev/null || echo "N/A"
echo "--- lvs ---"
$TIMEOUT lvs 2>/dev/null || echo "N/A"
echo "--- lvs -a (include internal) ---"
$TIMEOUT lvs -a 2>/dev/null || echo "N/A"
echo "--- lvs -o+data_percent,metadata_percent,snap_percent,lv_attr,lv_health_status ---"
$TIMEOUT lvs -a -o +data_percent,metadata_percent,snap_percent,lv_attr,lv_health_status 2>/dev/null || echo "N/A"

# Section H: Multipath
echo ""
echo "=== Section H: Multipath ==="
echo "--- multipath -ll ---"
$TIMEOUT multipath -ll 2>/dev/null || echo "N/A"
echo "--- multipathd status ---"
$TIMEOUT multipathd show status 2>/dev/null || echo "multipathd not running"
echo "--- multipathd paths ---"
$TIMEOUT multipathd show paths 2>/dev/null || echo "N/A"

# Section I: Kernel Logs
echo ""
echo "=== Section I: Kernel Logs ==="
echo "--- dmesg block/SCSI/DM/md messages ---"
$TIMEOUT dmesg 2>/dev/null | grep -E -i "I/O error|Buffer I/O|blk_update_request|device-mapper|md:|raid|sd[a-z].*error|SCSI.*error|ata.*error|hung_task|blocked for more than|end_request" | tail -30 || echo "N/A"

# Section J: D-state Processes
echo ""
echo "=== Section J: D-state Processes ==="
echo "--- D state process count ---"
d_cnt=$(ps aux 2>/dev/null | grep ' D' | grep -v grep | wc -l)
echo "Count: $d_cnt"
echo "--- Top 15 D state ---"
ps aux 2>/dev/null | grep ' D' | grep -v grep | head -15 || echo "(none)"

# Summary
echo ""
echo "=========================================="
echo " Collection complete. Output: $OUTDIR"
echo "=========================================="
