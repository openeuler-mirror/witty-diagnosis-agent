#!/usr/bin/env bash
# collect_mem_info.sh — 系统内存综合信息收集（基线）
set -euo pipefail
OUTDIR="/tmp/mem_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-p <pid>] [-n <name>] [-i <interval>] [-c <count>]"; exit 1; }
PID=""; PNAME=""; INTERVAL="10"; COUNT="2"
while getopts "p:n:i:c:" opt; do case $opt in
  p) PID="$OPTARG";; n) PNAME="$OPTARG";; i) INTERVAL="$OPTARG";; c) COUNT="$OPTARG";; *) usage;; esac; done

# 如果只给了进程名，尝试查找 PID
if [ -z "$PID" ] && [ -n "$PNAME" ]; then
  PID=$(pidof "$PNAME" 2>/dev/null | awk '{print $1}') || true
fi

echo "============================================"
echo "  System Memory Baseline Collection"
echo "  Target PID: ${PID:-N/A}"
echo "  Interval: ${INTERVAL}s, Count: ${COUNT}"
echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  OutDir: $OUTDIR"
echo "============================================"

for i in $(seq 1 "$COUNT"); do
  echo "--- Collection #$i (interval=${INTERVAL}s) ---"

  echo "--- M1. System Memory Overview ---"
  free -h | tee "$OUTDIR/free_${i}.txt"
  grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|Slab|SUnreclaim|VmallocUsed|AnonPages|PageTables" /proc/meminfo | tee "$OUTDIR/meminfo_${i}.txt"

  if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
    echo "--- M2. Process Memory (PID=$PID) ---"
    grep -E "VmRSS|VmPeak|VmSize|VmData|VmStk|VmPTE|RssAnon|RssFile" "/proc/$PID/status" 2>/dev/null | tee "$OUTDIR/proc_status_${i}.txt" || echo "[WARN] Process $PID not found"

    echo "--- M3. Process Memory Map (top 15 by RSS) ---"
    pmap -x "$PID" 2>/dev/null | sort -k3 -rn | head -15 | tee "$OUTDIR/pmap_${i}.txt" || true

    echo "--- M4. Anonymous Page Total ---"
    grep Anonymous "/proc/$PID/smaps" 2>/dev/null | awk '{sum+=$2} END{print sum " kB anonymous"}' | tee "$OUTDIR/anon_${i}.txt" || true
  fi

  echo "--- M5. Slab Allocator ---"
  if command -v slabtop &>/dev/null; then
    slabtop -o | head -15 | tee "$OUTDIR/slabtop_${i}.txt" || true
  fi
  cat /proc/slabinfo 2>/dev/null | head -10 | tee "$OUTDIR/slabinfo_header_${i}.txt" || true

  echo "--- M6. vmalloc Status ---"
  grep Vmalloc /proc/meminfo | tee "$OUTDIR/vmalloc_${i}.txt"
  cat /proc/vmallocinfo 2>/dev/null | head -20 | tee "$OUTDIR/vmallocinfo_${i}.txt" || true

  echo "--- M7. TOP Memory Consumers ---"
  ps aux --sort=-%mem 2>/dev/null | head -10 | tee "$OUTDIR/top_mem_${i}.txt" || true

  echo "--- M8. Kernel Memory ---"
  grep -E "Slab|SUnreclaim|VmallocUsed|PageTables|KernelStack" /proc/meminfo | tee "$OUTDIR/kernel_mem_${i}.txt"

  if [ -d "/sys/fs/cgroup/memory" ]; then
    echo "--- M9. Memcg Summary ---"
    for cg in /sys/fs/cgroup/memory/*/memory.usage_in_bytes; do
      [ -f "$cg" ] && echo "$(cat "$cg") $(dirname "$cg" | xargs basename)" >> "$OUTDIR/memcg_usage_${i}.txt"
    done
    echo "Memcg usage saved to $OUTDIR/memcg_usage_${i}.txt"
  fi

  echo "--- Collection #$i done ---"
  [ "$i" -lt "$COUNT" ] && sleep "$INTERVAL"
done

echo "============================================"
echo "[SUMMARY]"
echo "  Target PID: ${PID:-N/A}"
echo "  Data points: $COUNT"
echo "  Interval: ${INTERVAL}s"
echo "  Complete output saved to: $OUTDIR"
