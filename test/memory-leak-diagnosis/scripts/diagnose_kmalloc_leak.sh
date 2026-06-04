#!/usr/bin/env bash
# diagnose_kmalloc_leak.sh — 分支 F: kmalloc 未释放诊断
set -euo pipefail
OUTDIR="/tmp/kmalloc_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-i <interval>] [-c <count>]"; exit 1; }
INTERVAL="10"; COUNT="6"
while getopts "i:c:" opt; do case $opt in i) INTERVAL="$OPTARG";; c) COUNT="$OPTARG";; *) usage;; esac; done

echo "==========================================="
echo "  kmalloc Leak Diagnosis (Branch F)"
echo "  Interval: ${INTERVAL}s, Count: ${COUNT}"
echo "==========================================="

echo "--- F1. kmalloc Cache Overview ---"
cat /proc/slabinfo 2>/dev/null | grep "^kmalloc-" | sort -t- -k2 -n | tee "$OUTDIR/kmalloc_overview.txt"

echo ""
echo "--- F2. kmalloc Active Objects Trend ---"
echo "Time,CacheName,ActiveObjs,TotalObjs,ObjSize" > "$OUTDIR/kmalloc_trend.csv"
for i in $(seq 1 "$COUNT"); do
  TS=$(date '+%H:%M:%S')
  cat /proc/slabinfo 2>/dev/null | grep "^kmalloc-" | while read -r LINE; do
    NAME=$(echo "$LINE" | awk '{print $1}')
    ACTIVE=$(echo "$LINE" | awk '{print $2}')
    TOTAL=$(echo "$LINE" | awk '{print $3}')
    SIZE=$(echo "$LINE" | awk '{print $4}')
    echo "$TS,$NAME,$ACTIVE,$TOTAL,$SIZE" >> "$OUTDIR/kmalloc_trend.csv"
  done
  echo "[$TS] kmalloc snapshot taken" | tee -a "$OUTDIR/kmalloc_snapshots.txt"
  [ "$i" -lt "$COUNT" ] && sleep "$INTERVAL"
done

echo ""
echo "--- F3. kmalloc Cache Size Ranking ---"
cat /proc/slabinfo 2>/dev/null | grep "^kmalloc-" | awk '{mem=$4*$2/1024; print $1, $2, "active", mem " KB"}' | sort -k3 -rn | head -15 | tee "$OUTDIR/kmalloc_by_mem.txt"

echo ""
echo "--- F4. kmemleak Scan ---"
if [ -f /sys/kernel/debug/kmemleak ]; then
  echo "[INFO] Triggering kmemleak scan..."
  echo scan > /sys/kernel/debug/kmemleak 2>/dev/null || echo "[WARN] kmemleak requires root"
  cat /sys/kernel/debug/kmemleak 2>/dev/null | head -50 | tee "$OUTDIR/kmemleak_report.txt" || true
else
  echo "[INFO] kmemleak not available"
fi

echo ""
echo "--- F5. Non-kmalloc Slab Growth Check ---"
cat /proc/slabinfo 2>/dev/null | tail -n +3 | sort -k2 -rn | head -10 | tee "$OUTDIR/top_slab_growth.txt"

echo "==========================================="
echo "  Diagnosis Summary"
echo "  Data points: $COUNT (interval ${INTERVAL}s)"
echo "  Trend data: $OUTDIR/kmalloc_trend.csv"
echo "  Complete output saved to: $OUTDIR"
