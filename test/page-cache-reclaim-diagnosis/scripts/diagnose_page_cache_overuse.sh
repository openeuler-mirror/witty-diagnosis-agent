#!/usr/bin/env bash
# diagnose_page_cache_overuse.sh — 分支 D: page cache 过度占用诊断
set -euo pipefail
OUTDIR="/tmp/pagecache_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-S <start_time>]"; exit 1; }
while getopts "S:h" opt; do case $opt in S) START_TIME="$OPTARG";; h) usage;; esac; done

echo "==========================================="
echo "  Page Cache Overuse Diagnosis (Branch D)"
echo "==========================================="

echo "--- D1. Memory Overview ---"
MEMTOTAL=$(grep ^MemTotal /proc/meminfo | awk '{print $2}')
MEMFREE=$(grep ^MemFree /proc/meminfo | awk '{print $2}')
MEMAVAIL=$(grep ^MemAvailable /proc/meminfo | awk '{print $2}')
CACHED=$(grep ^Cached /proc/meminfo | awk '{print $2}')
BUFFERS=$(grep ^Buffers /proc/meminfo | awk '{print $2}')
SHMEM=$(grep ^Shmem /proc/meminfo | awk '{print $2}')

echo "MemTotal=${MEMTOTAL}kB MemFree=${MEMFREE}kB MemAvailable=${MEMAVAIL}kB"
echo "Cached=${CACHED}kB Buffers=${BUFFERS}kB Shmem=${SHMEM}kB"
CACHE_RATIO=$(echo "scale=1; $CACHED * 100 / $MEMTOTAL" | bc 2>/dev/null || echo "N/A")
echo "Cached/MemTotal: ${CACHE_RATIO}%"
AVAIL_RATIO=$(echo "scale=1; $MEMAVAIL * 100 / $MEMTOTAL" | bc 2>/dev/null || echo "N/A")
echo "MemAvailable/MemTotal: ${AVAIL_RATIO}%"

echo "--- D2. File-backed pages (pure page cache, excl tmpfs) ---"
FILE_CACHE=$((CACHED - SHMEM))
echo "File-backed page cache (Cached - Shmem): ${FILE_CACHE}kB"

echo "--- D3. Reclaim Pressure Settings ---"
echo "vm.vfs_cache_pressure = $(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo N/A)"
echo "vm.swappiness = $(sysctl -n vm.swappiness 2>/dev/null || echo N/A)"

echo "--- D4. Active/Inactive File Pages ---"
grep -E "nr_active_file|nr_inactive_file" /proc/vmstat

ACT_FILE=$(grep "^nr_active_file" /proc/vmstat | awk '{print $2}')
INACT_FILE=$(grep "^nr_inactive_file" /proc/vmstat | awk '{print $2}')
echo "Active(file)=${ACT_FILE}  Inactive(file)=${INACT_FILE}"
if [ "$INACT_FILE" -gt 0 ] 2>/dev/null; then
  echo "Act/Inact ratio: $(echo "scale=2; $ACT_FILE / $INACT_FILE" | bc 2>/dev/null || echo N/A)"
fi

echo "--- D5. Top File Cache Consumers (Top 5 by RSS) ---"
ps aux --sort=-%mem 2>/dev/null | head -6 || true

echo "==========================================="
echo "  Diagnosis Summary"
echo "  Cached: ${CACHE_RATIO}% of MemTotal (alarm if > 70%)"
echo "  MemAvailable: ${AVAIL_RATIO}% of MemTotal (alarm if < 20%)"
echo "  vfs_cache_pressure: $(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo N/A)"
echo "  Complete output saved to: $OUTDIR"
