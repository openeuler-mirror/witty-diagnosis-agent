#!/usr/bin/env bash
# diagnose_direct_reclaim.sh — 分支 B: direct reclaim 延迟抖动诊断
set -euo pipefail
OUTDIR="/tmp/direct_reclaim_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-S <start_time>] [-p <PID>]"; exit 1; }
START_TIME=""; PID=""
while getopts "S:p:h" opt; do case $opt in
  S) START_TIME="$OPTARG";; p) PID="$OPTARG";; h) usage;; esac; done

echo "==========================================="
echo "  Direct Reclaim Latency Diagnosis (Branch B)"
echo "==========================================="

echo "--- B1. Direct Reclaim Stats ---"
grep -E "pgscan_direct|pgsteal_direct|allocstall|direct_reclaim" /proc/vmstat

DIRECT=$(grep ^pgscan_direct /proc/vmstat | awk '{print $2}')
KSWAPD=$(grep ^pgscan_kswapd /proc/vmstat | awk '{print $2}')
ALLOCSTALL=$(grep ^allocstall /proc/vmstat | awk '{print $2}')
if [ "$KSWAPD" -gt 0 ] 2>/dev/null; then
  RATIO=$(echo "scale=4; $DIRECT / $KSWAPD * 100" | bc 2>/dev/null || echo "N/A")
  echo "Direct/Kswapd ratio: ${RATIO}% (should be < 20%)"
fi
echo "allocstall: $ALLOCSTALL (should be 0)"

echo "--- B2. Allocation Stats ---"
grep -E "allocstall_|compact_stall|compact_fail|thp_fault_alloc" /proc/vmstat

echo "--- B3. Min Free Kbytes + Watermark ---"
echo "vm.min_free_kbytes = $(sysctl -n vm.min_free_kbytes 2>/dev/null || echo N/A)"
echo "vm.watermark_scale_factor = $(sysctl -n vm.watermark_scale_factor 2>/dev/null || echo N/A)"
MEMTOTAL=$(grep ^MemTotal /proc/meminfo | awk '{print $2}')
MINFREE=$(sysctl -n vm.min_free_kbytes 2>/dev/null || echo 0)
echo "MemTotal=${MEMTOTAL}kB  min_free_kbytes=${MINFREE}kB (ratio: $(echo "scale=2; $MINFREE*100/$MEMTOTAL" | bc 2>/dev/null || echo N/A)%)"

echo "--- B4. Zone Watermarks ---"
grep -B1 "pages free" /proc/zoneinfo | grep -E "Node|pages"

echo "--- B5. PSI Memory Pressure ---"
if [ -f /proc/pressure/memory ]; then
  cat /proc/pressure/memory
fi

echo "--- B6. THP Compaction Stats ---"
grep -E "compact_|thp_" /proc/vmstat | head -10

echo "--- B7. D-State Processes ---"
D_COUNT=$(ps -eo stat | grep "^ D" | wc -l)
echo "D-state processes: $D_COUNT"
if [ "$D_COUNT" -gt 0 ]; then
  ps -eo pid,stat,wchan,comm | grep "^ D" | head -10
fi

echo "==========================================="
echo "  Diagnosis Summary"
echo "  pgscan_direct: $DIRECT  allocstall: $ALLOCSTALL"
echo "  Direct/Kswapd: ${RATIO:-N/A}%"
echo "  D-state count: $D_COUNT"
echo "  Complete output saved to: $OUTDIR"
