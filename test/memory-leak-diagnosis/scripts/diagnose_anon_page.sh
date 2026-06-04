#!/usr/bin/env bash
# diagnose_anon_page.sh — 分支 B: 匿名页泄漏诊断
set -euo pipefail
OUTDIR="/tmp/anon_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 -p <pid>"; exit 1; }
PID=""
while getopts "p:" opt; do case $opt in p) PID="$OPTARG";; *) usage;; esac; done
[ -z "$PID" ] && usage
[ ! -d "/proc/$PID" ] && echo "[ERROR] Process $PID not found" && exit 1

echo "==========================================="
echo "  Anonymous Page Leak Diagnosis (Branch B)"
echo "  Target PID: $PID"
echo "==========================================="

echo "--- B1. Anonymous Page Total ---"
ANON_TOTAL=$(grep Anonymous "/proc/$PID/smaps" 2>/dev/null | awk '{sum+=$2} END{print sum}')
echo "Anonymous total: ${ANON_TOTAL:-0} kB" | tee "$OUTDIR/anon_total.txt"

echo ""
echo "--- B2. Anonymous Page by Mapping ---"
# Safer parsing: extract address, size, and Anonymous kB per region
awk 'BEGIN{RS=""; FS="\n"} /Anonymous/{for(i=1;i<=NF;i++){if($i~/^[0-9a-f]/)addr=substr($i,1,12); if($i~/^Anonymous:/){split($i,a," "); print addr,a[2]" kB"}}}' "/proc/$PID/smaps" 2>/dev/null | tee "$OUTDIR/anon_by_region.txt" || true
echo "--- B2b. smaps_rollup Anonymous (faster, Linux 4.14+) ---"
if [ -f "/proc/$PID/smaps_rollup" ]; then
  grep -E "Anonymous|Pss|Rss" "/proc/$PID/smaps_rollup" 2>/dev/null | tee "$OUTDIR/smaps_rollup.txt"
else
  echo "[INFO] smaps_rollup not available (kernel < 4.14)"
fi

echo ""
echo "--- B3. Heap Region Analysis ---"
grep -A10 "\[heap\]" "/proc/$PID/smaps" 2>/dev/null | tee "$OUTDIR/heap_smaps.txt" || echo "[INFO] No [heap] mapping"

echo ""
echo "--- B4. Anonymous mmap Regions (non-heap, non-stack) ---"
grep -B5 "Anonymous:" "/proc/$PID/smaps" 2>/dev/null | grep -v "\[heap\]" | grep -v "\[stack\]" | head -30 | tee "$OUTDIR/anon_mmap.txt" || echo "[INFO] No anonymous mmap regions"

echo ""
echo "--- B5. Potential Cache/Buffer Regions ---"
pmap -x "$PID" 2>/dev/null | grep -E "anon|heap" | head -15 | tee "$OUTDIR/pmap_anon.txt" || true

echo "==========================================="
echo "  Diagnosis Summary"
echo "  Anonymous total: ${ANON_TOTAL:-N/A} kB"
echo "  Complete output saved to: $OUTDIR"
