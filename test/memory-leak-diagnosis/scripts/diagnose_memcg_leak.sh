#!/usr/bin/env bash
# diagnose_memcg_leak.sh — 分支 G: Memcg 内存泄漏诊断
set -euo pipefail
OUTDIR="/tmp/memcg_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 [-g <cgroup_path>]"; exit 1; }
CGROUP_PATH=""
while getopts "g:" opt; do case $opt in g) CGROUP_PATH="$OPTARG";; *) usage;; esac; done
[ -z "$CGROUP_PATH" ] && CGROUP_PATH="/sys/fs/cgroup/memory"

if [ ! -d "$CGROUP_PATH" ]; then
  echo "[ERROR] Cgroup path $CGROUP_PATH not found"
  exit 1
fi

echo "==========================================="
echo "  Memcg Leak Diagnosis (Branch G)"
echo "  Cgroup: $CGROUP_PATH"
echo "==========================================="

echo "--- G1. Memcg Usage Overview ---"
for f in usage_in_bytes max_usage_in_bytes failcnt limit_in_bytes; do
  fpath="$CGROUP_PATH/memory.$f"
  [ -f "$fpath" ] && echo "memory.$f: $(cat "$fpath")" | tee "$OUTDIR/memcg_${f}.txt"
done

echo ""
echo "--- G2. Memcg Detailed Stat ---"
cat "$CGROUP_PATH/memory.stat" 2>/dev/null | tee "$OUTDIR/memcg_stat.txt" || echo "[WARN] memory.stat not found"

echo ""
echo "--- G3. Kernel Memory Usage ---"
if [ -f "$CGROUP_PATH/memory.kmem.usage_in_bytes" ]; then
  echo "kmem usage: $(cat "$CGROUP_PATH/memory.kmem.usage_in_bytes") bytes" | tee "$OUTDIR/memcg_kmem.txt"
fi
if [ -f "$CGROUP_PATH/memory.kmem.slabinfo" ]; then
  cat "$CGROUP_PATH/memory.kmem.slabinfo" 2>/dev/null | tee "$OUTDIR/memcg_kmem_slab.txt" || true
fi

echo ""
echo "--- G4. RSS vs Memcg Usage Comparison ---"
USAGE=$(cat "$CGROUP_PATH/memory.usage_in_bytes" 2>/dev/null || echo 0)
# Convert memcg bytes to kB
USAGE_KB=$(( USAGE / 1024 ))
TOTAL_RSS=0
if [ -f "$CGROUP_PATH/cgroup.procs" ]; then
  while read -r pid; do
    [ -n "$pid" ] && [ -d "/proc/$pid" ] || continue
    RSS=$(grep VmRSS "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    [ -n "$RSS" ] && [ "$RSS" -eq "$RSS" ] 2>/dev/null && TOTAL_RSS=$((TOTAL_RSS + RSS))
  done < "$CGROUP_PATH/cgroup.procs"
fi
echo "memcg usage:          ${USAGE_KB} kB" | tee "$OUTDIR/rss_vs_memcg.txt"
echo "processes total RSS:  ${TOTAL_RSS} kB" | tee -a "$OUTDIR/rss_vs_memcg.txt"
DIFF=$(( USAGE_KB - TOTAL_RSS ))
echo "difference:           ${DIFF} kB (memcg > RSS = kernel memory)" | tee -a "$OUTDIR/rss_vs_memcg.txt"

echo ""
echo "--- G5. Memcg Pressure Level ---"
if [ -f "$CGROUP_PATH/memory.pressure_level" ]; then
  cat "$CGROUP_PATH/memory.pressure_level" | tee "$OUTDIR/memcg_pressure.txt" || true
fi

echo ""
echo "--- G6. OOM Control ---"
[ -f "$CGROUP_PATH/memory.oom_control" ] && cat "$CGROUP_PATH/memory.oom_control" | tee "$OUTDIR/memcg_oom.txt"

echo ""
echo "--- G7. Swap Usage (if any) ---"
[ -f "$CGROUP_PATH/memory.swap.usage_in_bytes" ] && echo "swap: $(cat "$CGROUP_PATH/memory.swap.usage_in_bytes") bytes" | tee "$OUTDIR/memcg_swap.txt" || echo "[INFO] No swap accounting"

echo "==========================================="
echo "  Diagnosis Summary"
echo "  memcg usage: ${USAGE_KB} kB"
echo "  Process RSS total: ${TOTAL_RSS} kB"
echo "  Difference: ${DIFF} kB"
echo "  Complete output saved to: $OUTDIR"
