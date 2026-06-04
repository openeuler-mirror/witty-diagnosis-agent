#!/usr/bin/env bash
# diagnose_slab_leak.sh — 分支 D: Slab 缓存泄漏诊断
set -euo pipefail
OUTDIR="/tmp/slab_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-i <interval>] [-c <count>]"; exit 1; }
INTERVAL="10"; COUNT="6"
while getopts "i:c:" opt; do case $opt in i) INTERVAL="$OPTARG";; c) COUNT="$OPTARG";; *) usage;; esac; done

echo "==========================================="
echo "  Slab Leak Diagnosis (Branch D)"
echo "  Interval: ${INTERVAL}s, Count: ${COUNT}"
echo "==========================================="

grep -E "Slab|SUnreclaim|SReclaimable" /proc/meminfo | tee "$OUTDIR/slab_baseline.txt"

echo ""
echo "--- D1. TOP Slab Caches (by active objects) ---"
cat /proc/slabinfo 2>/dev/null | head -1 | tee "$OUTDIR/slabinfo_header.txt"
cat /proc/slabinfo 2>/dev/null | tail -n +3 | sort -k2 -rn | head -20 | tee "$OUTDIR/slab_top_active.txt"

echo ""
echo "--- D2. Slab Cache Trend Monitoring ---"
echo "Time,CacheName,ActiveObjs,TotalObjs,ObjSize" > "$OUTDIR/slab_trend.csv"
CACHES=(dentry inode_cache radix_tree_node)
for i in $(seq 1 "$COUNT"); do
  TS=$(date '+%H:%M:%S')
  # Snapshot each leak-prone cache at the same time point
  for CACHE in "${CACHES[@]}"; do
    LINE=$(cat /proc/slabinfo 2>/dev/null | grep "^$CACHE " | head -1)
    if [ -n "$LINE" ]; then
      NAME=$(echo "$LINE" | awk '{print $1}')
      ACTIVE=$(echo "$LINE" | awk '{print $2}')
      TOTAL=$(echo "$LINE" | awk '{print $3}')
      SIZE=$(echo "$LINE" | awk '{print $4}')
      echo "$TS,$NAME,$ACTIVE,$TOTAL,$SIZE" >> "$OUTDIR/slab_trend.csv"
      echo "  [$TS] $NAME: active=$ACTIVE total=$TOTAL"
    fi
  done
  # Also capture top 5 kmalloc-* at each time point
  cat /proc/slabinfo 2>/dev/null | grep "^kmalloc-" | sort -k2 -rn | head -5 | while read -r LINE; do
    NAME=$(echo "$LINE" | awk '{print $1}')
    ACTIVE=$(echo "$LINE" | awk '{print $2}')
    TOTAL=$(echo "$LINE" | awk '{print $3}')
    SIZE=$(echo "$LINE" | awk '{print $4}')
    echo "$TS,$NAME,$ACTIVE,$TOTAL,$SIZE" >> "$OUTDIR/slab_trend.csv"
    echo "  [$TS] $NAME: active=$ACTIVE total=$TOTAL"
  done
  [ "$i" -lt "$COUNT" ] && sleep "$INTERVAL"
done

echo ""
echo "--- D3. SUnreclaim (Unreclaimable Slab) ---"
grep SUnreclaim /proc/meminfo | tee "$OUTDIR/sunreclaim.txt"

echo ""
echo "--- D4. Slab Cache Size Ranking (by memory used) ---"
cat /proc/slabinfo 2>/dev/null | tail -n +3 | awk '{mem=$4*$3/1024; print $1, mem " KB"}' | sort -k2 -rn | head -15 | tee "$OUTDIR/slab_by_mem.txt"

echo "==========================================="
echo "  Diagnosis Summary"
echo "  Data points: $COUNT (interval ${INTERVAL}s)"
echo "  Trend data: $OUTDIR/slab_trend.csv"
echo "  Complete output saved to: $OUTDIR"
