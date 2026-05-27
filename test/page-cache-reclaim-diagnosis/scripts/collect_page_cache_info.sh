#!/usr/bin/env bash
# collect_page_cache_info.sh — 页缓存/回收综合信息收集（基线）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="/tmp/page_cache_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-S <start_time>] [-E <end_time>] [-p <PID>] [-n <name>]"; exit 1; }
START_TIME=""; END_TIME=""; PID=""; NAME=""
while getopts "S:E:p:n:h" opt; do case $opt in
  S) START_TIME="$OPTARG";; E) END_TIME="$OPTARG";; p) PID="$OPTARG";; n) NAME="$OPTARG";; h) usage;; esac; done

echo "============================================"
echo "  Page Cache / Reclaim Baseline Collection"
echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  OutDir: $OUTDIR"
echo "============================================"

echo "--- S1. Memory Overview ---"
cat /proc/meminfo | tee "$OUTDIR/meminfo.txt"

echo "--- S2. VM Reclaim Stats ---"
grep -E "pgscan|pgsteal|allocstall|kswapd|compact|pgmajfault|nr_dirty|nr_writeback" /proc/vmstat | tee "$OUTDIR/vmstat_reclaim.txt"

echo "--- S3. Full vmstat ---"
cat /proc/vmstat > "$OUTDIR/vmstat_full.txt"

echo "--- S4. Zone Info (LRU+Watermark) ---"
cat /proc/zoneinfo > "$OUTDIR/zoneinfo.txt"

echo "--- S5. Buddy Info (Fragmentation) ---"
cat /proc/buddyinfo | tee "$OUTDIR/buddyinfo.txt"

echo "--- S6. PSI Memory Pressure ---"
if [ -f /proc/pressure/memory ]; then
  cat /proc/pressure/memory | tee "$OUTDIR/psi_memory.txt"
fi

echo "--- S7. KSWAPD Status ---"
KSWAPD_PID=$(pgrep -f "kswapd" | head -1 || echo "N/A")
if [ "$KSWAPD_PID" != "N/A" ]; then
  echo "kswapd0 PID=$KSWAPD_PID"
  ps -p "$KSWAPD_PID" -o pid,%cpu,%mem,comm --no-headers 2>/dev/null | tee "$OUTDIR/kswapd_cpu.txt"
else
  echo "kswapd0 not found (may be running inside container)"
fi

echo "--- S8. Sysctl VM Params ---"
for p in dirty_ratio dirty_background_ratio dirty_writeback_centisecs dirty_expire_centisecs vfs_cache_pressure swappiness min_free_kbytes watermark_scale_factor zone_reclaim_mode; do
  echo "vm.$p = $(sysctl -n vm.$p 2>/dev/null || echo 'N/A')"
done > "$OUTDIR/sysctl_vm.txt"
cat "$OUTDIR/sysctl_vm.txt"

echo "--- S9. Kernel Log (Reclaim/OOM/Allocstall) ---"
if command -v dmesg &>/dev/null; then
  dmesg -T 2>/dev/null | grep -iE "reclaim|allocstall|OOM|kswapd|page allocation failure|out of memory" | tail -30 > "$OUTDIR/kern_log_reclaim.txt" || true
  cat "$OUTDIR/kern_log_reclaim.txt"
fi

echo "--- S10. Target Process (if specified) ---"
if [ -n "$PID" ]; then
  echo "PID=$PID"
  cat /proc/$PID/status 2>/dev/null > "$OUTDIR/pid_${PID}_status.txt" || echo "PID $PID not found"
fi
if [ -n "$NAME" ]; then
  PIDS=$(pgrep -f "$NAME" | head -5)
  for p in $PIDS; do
    cat /proc/$p/status 2>/dev/null > "$OUTDIR/pid_${p}_${NAME}_status.txt" || true
  done
fi

echo "============================================"
echo "[SUMMARY]"
echo "  MemFree=$(grep ^MemFree /proc/meminfo | awk '{print $2}') kB"
echo "  MemAvailable=$(grep ^MemAvailable /proc/meminfo | awk '{print $2}') kB"
echo "  Cached=$(grep ^Cached /proc/meminfo | awk '{print $2}') kB"
echo "  Dirty=$(grep ^Dirty /proc/meminfo | awk '{print $2}') kB"
echo "  Writeback=$(grep ^Writeback /proc/meminfo | awk '{print $2}') kB"
echo "  Allocstall=$(grep ^allocstall /proc/vmstat | awk '{print $2}')"
echo "  PgscanKswapd=$(grep ^pgscan_kswapd /proc/vmstat | awk '{print $2}')"
echo "  PgscanDirect=$(grep ^pgscan_direct /proc/vmstat | awk '{print $2}')"
echo "  Complete output saved to: $OUTDIR"
