#!/usr/bin/env bash
# diagnose_kswapd.sh — 分支 A: kswapd 高 CPU 诊断
set -euo pipefail
OUTDIR="/tmp/kswapd_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-S <start_time>] [-p <PID>]"; exit 1; }
START_TIME=""; PID=""
while getopts "S:p:h" opt; do case $opt in
  S) START_TIME="$OPTARG";; p) PID="$OPTARG";; h) usage;; esac; done

echo "==========================================="
echo "  KSWAPD High CPU Diagnosis (Branch A)"
echo "==========================================="

echo "--- A1. KSWAPD CPU Usage ---"
KSWAPD_PID=$(pgrep -f "kswapd" | head -1 || echo "N/A")
if [ "$KSWAPD_PID" != "N/A" ]; then
  ps -p "$KSWAPD_PID" -o pid,%cpu,%mem,comm,etime --no-headers 2>/dev/null
  echo "kswapd0 PID=$KSWAPD_PID"
else
  echo "kswapd0 not found (container?)"
fi

echo "--- A2. Reclaim Scan/Steal Stats ---"
grep -E "pgscan_kswapd|pgsteal_kswapd|kswapd_steal|kswapd_inodesteal" /proc/vmstat

SCAN=$(grep ^pgscan_kswapd /proc/vmstat | awk '{print $2}')
STEAL=$(grep ^pgsteal_kswapd /proc/vmstat | awk '{print $2}')
if [ "$STEAL" -gt 0 ] 2>/dev/null; then
  RATIO=$(echo "scale=2; $SCAN / $STEAL" | bc 2>/dev/null || echo "N/A")
  echo "Scan/Steal Ratio: $RATIO (should be < 2)"
fi

echo "--- A3. Memory Watermarks ---"
grep -E "min|low|high" /proc/zoneinfo | grep -v "protection" | head -30

echo "--- A4. LRU List Sizes ---"
grep -E "nr_active_anon|nr_inactive_anon|nr_active_file|nr_inactive_file|nr_unevictable" /proc/zoneinfo | head -20

ANON_ACTIVE=$(grep "^      nr_active_anon" /proc/zoneinfo | awk '{s+=$2}END{print s}')
ANON_INACTIVE=$(grep "^      nr_inactive_anon" /proc/zoneinfo | awk '{s+=$2}END{print s}')
FILE_ACTIVE=$(grep "^      nr_active_file" /proc/zoneinfo | awk '{s+=$2}END{print s}')
FILE_INACTIVE=$(grep "^      nr_inactive_file" /proc/zoneinfo | awk '{s+=$2}END{print s}')
echo "Active(anon)=$ANON_ACTIVE  Inactive(anon)=$ANON_INACTIVE"
echo "Active(file)=$FILE_ACTIVE  Inactive(file)=$FILE_INACTIVE"

echo "--- A5. Fragmentation (Buddy Info) ---"
cat /proc/buddyinfo

echo "--- A6. Slab Unreclaimable ---"
grep -E "Slab|SUnreclaim" /proc/meminfo

echo "--- A7. Kernel Reclaim Log ---"
dmesg -T 2>/dev/null | grep -iE "reclaim|kswapd" | tail -10 || echo "(no recent reclaim logs)"

echo "==========================================="
echo "  Diagnosis Summary"
echo "  kswapd PID: $KSWAPD_PID"
echo "  pgscan_kswapd: $SCAN  pgsteal: $STEAL  ratio: ${RATIO:-N/A}"
echo "  Active(anon)=${ANON_ACTIVE:-0}  Inactive(anon)=${ANON_INACTIVE:-0}"
echo "  Active(file)=${FILE_ACTIVE:-0}  Inactive(file)=${FILE_INACTIVE:-0}"
echo "  Complete output saved to: $OUTDIR"
