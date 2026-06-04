#!/usr/bin/env bash
# diagnose_vmalloc_leak.sh — 分支 E: vmalloc 泄漏诊断
set -euo pipefail
OUTDIR="/tmp/vmalloc_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-i <interval>] [-c <count>]"; exit 1; }
INTERVAL="10"; COUNT="3"
while getopts "i:c:" opt; do case $opt in i) INTERVAL="$OPTARG";; c) COUNT="$OPTARG";; *) usage;; esac; done

echo "==========================================="
echo "  vmalloc Leak Diagnosis (Branch E)"
echo "  Interval: ${INTERVAL}s, Count: ${COUNT}"
echo "==========================================="

echo "--- E1. vmalloc Memory Overview ---"
grep Vmalloc /proc/meminfo | tee "$OUTDIR/vmalloc_baseline.txt"

echo ""
echo "--- E2. vmalloc Trend Monitoring ---"
echo "Time,VmallocUsed,VmallocChunk,VmallocTotal" > "$OUTDIR/vmalloc_trend.csv"
for i in $(seq 1 "$COUNT"); do
  TS=$(date '+%H:%M:%S')
  USED=$(grep VmallocUsed /proc/meminfo | awk '{print $2}' || echo 0)
  CHUNK=$(grep VmallocChunk /proc/meminfo | awk '{print $2}' || echo 0)
  TOTAL=$(grep VmallocTotal /proc/meminfo | awk '{print $2}' || echo 0)
  echo "$TS,$USED,$CHUNK,$TOTAL" >> "$OUTDIR/vmalloc_trend.csv"
  echo "[$TS] VmallocUsed=$USED kB VmallocChunk=$CHUNK kB"
  [ "$i" -lt "$COUNT" ] && sleep "$INTERVAL"
done

echo ""
echo "--- E3. vmalloc Allocations Detail ---"
cat /proc/vmallocinfo 2>/dev/null | tee "$OUTDIR/vmallocinfo_full.txt"
TOTAL_VMALLOC=$(cat /proc/vmallocinfo 2>/dev/null | awk '{sum+=$2} END{print sum/1024 " MB"}' || echo "N/A")
echo "Total vmalloc allocated: $TOTAL_VMALLOC" | tee -a "$OUTDIR/vmalloc_total.txt"

echo ""
echo "--- E4. vmalloc by Caller (top allocators) ---"
cat /proc/vmallocinfo 2>/dev/null | awk '{print $4}' | sort | uniq -c | sort -rn | head -15 | tee "$OUTDIR/vmalloc_by_caller.txt"

echo ""
echo "--- E5. Large vmalloc Regions (>1MB) ---"
cat /proc/vmallocinfo 2>/dev/null | awk '$2 > 1048576 {printf "%s %d KB %s\n", $1, $2/1024, $4}' | sort -k2 -rn | head -20 | tee "$OUTDIR/vmalloc_large.txt"

echo ""
echo "--- E6. Fragmentation Check ---"
TOTAL=$(grep VmallocTotal /proc/meminfo | awk '{print $2}')
USED=$(grep VmallocUsed /proc/meminfo | awk '{print $2}')
CHUNK=$(grep VmallocChunk /proc/meminfo | awk '{print $2}')
if [ "$USED" -gt 0 ] 2>/dev/null; then
  RATIO=$((CHUNK * 100 / USED))
  echo "VmallocChunk/VmallocUsed: ${RATIO}%"
  if [ "$RATIO" -lt 30 ] 2>/dev/null; then
    echo "[WARN] Low VmallocChunk indicates fragmentation"
  else
    echo "[OK] VmallocChunk is healthy"
  fi
fi | tee "$OUTDIR/vmalloc_frag.txt"

echo ""
echo "--- E7. kmemleak Scan (if available) ---"
if [ -f /sys/kernel/debug/kmemleak ]; then
  echo "[INFO] Triggering kmemleak scan..."
  echo scan > /sys/kernel/debug/kmemleak 2>/dev/null || echo "[WARN] kmemleak scan requires root"
  cat /sys/kernel/debug/kmemleak 2>/dev/null | head -40 | tee "$OUTDIR/kmemleak_report.txt" || echo "[INFO] No kmemleak results (try as root)"
else
  echo "[INFO] kmemleak not available (requires CONFIG_DEBUG_KMEMLEAK)"
fi

echo "==========================================="
echo "  Diagnosis Summary"
echo "  Total vmalloc: $TOTAL_VMALLOC"
echo "  Trend data: $OUTDIR/vmalloc_trend.csv"
echo "  Complete output saved to: $OUTDIR"
