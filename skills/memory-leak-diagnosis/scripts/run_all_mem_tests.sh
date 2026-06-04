#!/bin/bash
# run_all_mem_tests.sh — 全 7 分支 内存泄漏故障注入与诊断测试
set -e
OUTDIR="/tmp/mem_test_results"
mkdir -p "$OUTDIR"
PIDS=""

cleanup() {
  echo "=== Cleaning up fault injectors ==="
  for pid in $(jobs -p 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
  pkill -f "fault_heap_leak" 2>/dev/null || true
  pkill -f "fault_mmap_anon_leak" 2>/dev/null || true
  pkill -f "fault_thread_leak" 2>/dev/null || true
  pkill -f "fault_fd_leak" 2>/dev/null || true
  sleep 1
  echo "=== Cleanup done ==="
}
trap cleanup EXIT

echo "================================================"
echo "  Memory Leak Diagnosis — Full Test Suite"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"

# ---- Compile C fault injectors ----
echo ""
echo "=== Compiling fault injectors ==="
gcc -g -O0 -o /tmp/fault_heap_leak /test/fault_heap_leak.c 2>&1 || echo "[WARN] gcc not available, using Python fallback"
gcc -g -O0 -o /tmp/fault_mmap_anon_leak /test/fault_mmap_anon_leak.c 2>&1 || echo "[WARN] mmap injector compile failed"

# ---- Start fault injectors ----
echo ""
echo "=== Starting fault injectors ==="

# Injector 1 (Branch A/C): Gradual heap leak — 5 MB/s, runs 60s
if [ -x /tmp/fault_heap_leak ]; then
  /tmp/fault_heap_leak 5 60 &
else
  python3 /test/fault_heap_leak_v2.py 5 60 &
fi
PIDS="$PIDS $!"
echo "  [Injector 1] Heap leak (5 MB/s) — PID $!"

# Injector 2 (Branch B): Anonymous mmap leak — 8 MB/s, runs 50s
if [ -x /tmp/fault_mmap_anon_leak ]; then
  /tmp/fault_mmap_anon_leak 8 50 &
  PIDS="$PIDS $!"
  echo "  [Injector 2] mmap anon leak (8 MB/s) — PID $!"
fi

# Injector 3 (Branch A3): Thread leak — 1 thread/sec, 3 MB each
python3 /test/fault_thread_leak.py 1 3 30 &
PIDS="$PIDS $!"
echo "  [Injector 3] Thread leak (1 thr/s, 3 MB) — PID $!"

# Injector 4 (Branch A4): FD leak
python3 /test/fault_fd_leak.py 5 50 &
PIDS="$PIDS $!"
echo "  [Injector 4] FD leak (5/s, hold 50) — PID $!"

echo ""
echo "=== Waiting for injectors to stabilize (5s) ==="
sleep 5

# ---- Run baseline collection ----
echo ""
echo "================================================"
echo "  Phase 1: Baseline Collection"
echo "================================================"
echo ""
bash /skills/memory-leak-diagnosis/collect_mem_info.sh -p 1 -i 3 -c 3 2>&1 | tee "$OUTDIR/phase1_baseline.txt"
echo ""

# ---- Run diagnostic scripts ----
echo "================================================"
echo "  Running Branch A: RSS Growth"
echo "================================================"
HEAP_PID=$(pgrep -f "fault_heap_leak" | head -1 || echo 1)
bash /skills/memory-leak-diagnosis/diagnose_rss_growth.sh -p "$HEAP_PID" -i 2 -c 5 2>&1 | tee "$OUTDIR/branch_a_rss_growth.txt"

echo ""
echo "================================================"
echo "  Running Branch B: Anonymous Page"
echo "================================================"
MMAP_PID=$(pgrep -f "fault_mmap_anon_leak" | head -1 || echo 1)
bash /skills/memory-leak-diagnosis/diagnose_anon_page.sh -p "$MMAP_PID" 2>&1 | tee "$OUTDIR/branch_b_anon_page.txt"

echo ""
echo "================================================"
echo "  Running Branch C: Heap Profiler"
echo "================================================"
bash /skills/memory-leak-diagnosis/diagnose_heap_profiler.sh -p "$HEAP_PID" -b /tmp/fault_heap_leak 2>&1 | tee "$OUTDIR/branch_c_heap.txt"

echo ""
echo "================================================"
echo "  Running Branch D: Slab Leak"
echo "================================================"
bash /skills/memory-leak-diagnosis/diagnose_slab_leak.sh -i 3 -c 4 2>&1 | tee "$OUTDIR/branch_d_slab.txt"

echo ""
echo "================================================"
echo "  Running Branch E: vmalloc Leak"
echo "================================================"
bash /skills/memory-leak-diagnosis/diagnose_vmalloc_leak.sh -i 3 -c 3 2>&1 | tee "$OUTDIR/branch_e_vmalloc.txt"

echo ""
echo "================================================"
echo "  Running Branch F: kmalloc"
echo "================================================"
bash /skills/memory-leak-diagnosis/diagnose_kmalloc_leak.sh -i 3 -c 4 2>&1 | tee "$OUTDIR/branch_f_kmalloc.txt"

echo ""
echo "================================================"
echo "  Running Branch G: Memcg"
echo "================================================"
bash /skills/memory-leak-diagnosis/diagnose_memcg_leak.sh 2>&1 | tee "$OUTDIR/branch_g_memcg.txt"

# ---- Summary ----
echo ""
echo "================================================"
echo "  ALL TESTS COMPLETE"
echo "  Results saved to: $OUTDIR"
echo "================================================"
ls -la "$OUTDIR"/
