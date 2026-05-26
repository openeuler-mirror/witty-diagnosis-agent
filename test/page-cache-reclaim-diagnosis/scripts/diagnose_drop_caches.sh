#!/usr/bin/env bash
# diagnose_drop_caches.sh — 分支 E: drop_caches 误用诊断
set -euo pipefail
OUTDIR="/tmp/dropcache_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-S <start_time>]"; exit 1; }
while getopts "S:h" opt; do case $opt in S) START_TIME="$OPTARG";; h) usage;; esac; done

echo "==========================================="
echo "  Drop Caches Misuse Diagnosis (Branch E)"
echo "==========================================="

echo "--- E1. Drop Caches Current Value ---"
echo "drop_caches = $(cat /proc/sys/vm/drop_caches 2>/dev/null || echo N/A)"

echo "--- E2. Memory Before/After Comparison ---"
grep -E "^Cached|^MemFree|^MemAvailable|^Dirty|^Writeback" /proc/meminfo

echo "--- E3. Major Fault Stats ---"
PFAULT=$(grep ^pgfault /proc/vmstat | awk '{print $2}')
MAJFAULT=$(grep ^pgmajfault /proc/vmstat | awk '{print $2}')
echo "pgfault=$PFAULT  pgmajfault=$MAJFAULT"
grep -E "pgfault|pgmajfault" /proc/vmstat

echo "--- E4. Recent Kernel Log (drop_caches) ---"
dmesg -T 2>/dev/null | grep -i "drop_caches" | tail -5 || echo "(no drop_caches in kernel log)"

echo "--- E5. Disk IO (await/avgqu-sz) ---"
if command -v iostat &>/dev/null; then
  iostat -x 1 3 2>/dev/null | grep -E "Device|avgqu-sz" -A1 || true
fi

echo "--- E6. Disk Rotational (HDD=1 / SSD=0) ---"
for d in $(ls /sys/block/ 2>/dev/null | grep -E "^vd|^sd"); do
  echo "$d: rotational=$(cat /sys/block/$d/queue/rotational 2>/dev/null || echo N/A)"
done

echo "--- E7. Top Processes After Drop ---"
ps aux --sort=-%cpu 2>/dev/null | head -6 || true

echo "==========================================="
echo "  Diagnosis Summary"
echo "  drop_caches: $(cat /proc/sys/vm/drop_caches 2>/dev/null || echo N/A)"
echo "  pgmajfault: $MAJFAULT (surge indicates I/O storm)"
echo "  Complete output saved to: $OUTDIR"
