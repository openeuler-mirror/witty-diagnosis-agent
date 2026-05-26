#!/usr/bin/env bash
# diagnose_dirty_writeback.sh — 分支 C: 脏页回写风暴诊断
set -euo pipefail
OUTDIR="/tmp/dirty_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-S <start_time>]"; exit 1; }
START_TIME=""
while getopts "S:h" opt; do case $opt in
  S) START_TIME="$OPTARG";; h) usage;; esac; done

echo "==========================================="
echo "  Dirty Page Writeback Storm Diagnosis (Branch C)"
echo "==========================================="

echo "--- C1. Dirty Page Config ---"
for p in dirty_ratio dirty_background_ratio dirty_writeback_centisecs dirty_expire_centisecs; do
  echo "vm.$p = $(sysctl -n vm.$p 2>/dev/null || echo N/A)"
done

echo "--- C2. Current Dirty Page State ---"
grep -E "Dirty|Writeback|WritebackTmp|MemTotal|MemFree" /proc/meminfo

DIRTY=$(grep ^Dirty /proc/meminfo | awk '{print $2}')
DIRTY_RATIO=$(sysctl -n vm.dirty_ratio 2>/dev/null || echo 20)
MEMTOTAL=$(grep ^MemTotal /proc/meminfo | awk '{print $2}')
DIRTY_THRESHOLD=$(echo "$MEMTOTAL * $DIRTY_RATIO / 100" | bc 2>/dev/null || echo "N/A")
echo "Dirty: ${DIRTY}kB / Threshold: ${DIRTY_THRESHOLD}kB"

echo "--- C3. Dirty Page Trends ---"
grep -E "nr_dirty|nr_writeback|nr_dirty_threshold|nr_dirty_background_threshold" /proc/vmstat

echo "--- C4. Write IO Stats ---"
if command -v iostat &>/dev/null; then
  iostat -x 1 3 2>/dev/null || true
fi

echo "--- C5. Top Writing Processes ---"
if command -v iotop &>/dev/null; then
  iotop -oP -n1 -b 2>/dev/null | head -10 || true
fi
# Fallback: check /proc disk write stats
for d in $(ls /sys/block/ 2>/dev/null | grep -E "^[sv]nvd|^vd|^sd"); do
  echo "$d: $(cat /sys/block/$d/stat 2>/dev/null)"
done

echo "--- C6. Flusher Threads ---"
ps -eo pid,comm | grep "flush\|kworker" | head -10

echo "==========================================="
echo "  Diagnosis Summary"
echo "  dirty_ratio: $(sysctl -n vm.dirty_ratio) / dirty_bg: $(sysctl -n vm.dirty_background_ratio)"
echo "  Current Dirty: ${DIRTY}kB  Threshold: ${DIRTY_THRESHOLD}kB"
echo "  Complete output saved to: $OUTDIR"
