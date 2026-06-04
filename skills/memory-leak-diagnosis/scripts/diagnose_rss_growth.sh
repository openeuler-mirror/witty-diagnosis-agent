#!/usr/bin/env bash
# diagnose_rss_growth.sh — 分支 A: 用户态 RSS 持续增长诊断
set -euo pipefail
OUTDIR="/tmp/rss_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 -p <pid> [-i <interval>] [-c <count>]"; exit 1; }
PID=""; INTERVAL="5"; COUNT="5"
while getopts "p:i:c:" opt; do case $opt in p) PID="$OPTARG";; i) INTERVAL="$OPTARG";; c) COUNT="$OPTARG";; *) usage;; esac; done
[ -z "$PID" ] && usage
[ ! -d "/proc/$PID" ] && echo "[ERROR] Process $PID not found" && exit 1

echo "==========================================="
echo "  RSS Growth Diagnosis (Branch A)"
echo "  Target PID: $PID"
echo "  Interval: ${INTERVAL}s, Count: ${COUNT}"
echo "==========================================="

echo "--- A1. Process Memory Status ---"
grep -E "VmRSS|VmPeak|VmSize|VmData|VmStk|VmPTE|Threads" "/proc/$PID/status" | tee "$OUTDIR/proc_status_base.txt"

echo ""
echo "--- A2. RSS Trend Monitoring ---"
echo "Time,VmRSS,VmData,VmStk,VmPTE,Threads" > "$OUTDIR/rss_trend.csv"
for i in $(seq 1 "$COUNT"); do
  TS=$(date '+%H:%M:%S')
  VMRSS=$(grep VmRSS "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "N/A")
  VMDATA=$(grep VmData "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "N/A")
  VMSTK=$(grep VmStk "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "N/A")
  VMPTE=$(grep VmPTE "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "N/A")
  THR=$(grep Threads "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "N/A")
  echo "$TS,$VMRSS,$VMDATA,$VMSTK,$VMPTE,$THR" >> "$OUTDIR/rss_trend.csv"
  echo "[$TS] VmRSS=$VMRSS VmData=$VMDATA VmStk=$VMSTK Threads=$THR"
  [ "$i" -lt "$COUNT" ] && sleep "$INTERVAL"
done

echo ""
echo "--- A3. Top Memory Mappings ---"
pmap -x "$PID" 2>/dev/null | sort -k3 -rn | head -15 | tee "$OUTDIR/pmap_top.txt" || true

echo ""
echo "--- A4. Heap vs Anonymous Analysis ---"
[ -f "/proc/$PID/smaps" ] && grep -E "\[heap\]|Anonymous" "/proc/$PID/smaps" | head -20 | tee "$OUTDIR/heap_anon.txt"

echo ""
echo "--- A5. Shared Memory Check ---"
SHM_COUNT=$(ipcs -m 2>/dev/null | wc -l || echo 0)
SHM_SIZE=$(df /dev/shm 2>/dev/null | awk 'NR==2{print $3}' || echo "N/A")
echo "Shared memory segments: $SHM_COUNT" | tee "$OUTDIR/shm_segments.txt"
echo "/dev/shm usage: ${SHM_SIZE:-N/A}" | tee -a "$OUTDIR/shm_segments.txt"
echo "--- A6. File Descriptor Count ---"
FD_COUNT=$(ls -1 "/proc/$PID/fd" 2>/dev/null | wc -l || echo 0)
echo "Open fds: $FD_COUNT" | tee -a "$OUTDIR/fd_count.txt"

echo "==========================================="
echo "  Diagnosis Summary"
echo "  PID: $PID"
echo "  Data points: $COUNT (interval ${INTERVAL}s)"
echo "  Trend data: $OUTDIR/rss_trend.csv"
echo "  Complete output saved to: $OUTDIR"
