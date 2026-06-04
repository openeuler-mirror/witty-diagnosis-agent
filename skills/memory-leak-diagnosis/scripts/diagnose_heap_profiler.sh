#!/usr/bin/env bash
# diagnose_heap_profiler.sh — 分支 C: Valgrind/ASan 堆泄漏诊断
set -euo pipefail
OUTDIR="/tmp/heap_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 -p <pid> [-b <binary>]"; exit 1; }
PID=""; BINARY=""
while getopts "p:b:" opt; do case $opt in p) PID="$OPTARG";; b) BINARY="$OPTARG";; *) usage;; esac; done
[ -z "$PID" ] && usage

echo "==========================================="
echo "  Heap Profiler Diagnosis (Branch C)"
echo "  Target PID: $PID"
echo "==========================================="

echo "--- C1. Memory Allocation Tracing (strace summary) ---"
echo "[INFO] Tracing memory syscalls via strace for 5 seconds..."
strace -p "$PID" -e trace=brk,mmap -c 2>&1 | tee "$OUTDIR/strace_summary.txt" &
STRACE_PID=$!
sleep 5
kill "$STRACE_PID" 2>/dev/null || true
wait "$STRACE_PID" 2>/dev/null || true
echo "[INFO] Strace summary saved to $OUTDIR/strace_summary.txt"

echo ""
echo "--- C2. Heap Usage from pmap ---"
pmap -x "$PID" 2>/dev/null | grep -E "heap|anon" | tee "$OUTDIR/pmap_heap.txt" || echo "[INFO] No heap section in pmap"

echo ""
echo "--- C3. VmData (Data+Heap) Size ---"
grep VmData "/proc/$PID/status" 2>/dev/null | tee "$OUTDIR/vmdata.txt" || true

echo ""
echo "--- C4. glibc Arena Estimation ---"
# Count anonymous mmap regions that are likely malloc arenas (size >= 64MB typically)
ANON_MMAP_COUNT=$(grep -c "^[0-9a-f]" "/proc/$PID/smaps" 2>/dev/null || echo 0)
LARGE_ANON=$(grep -B1 "Anonymous:.*[0-9]" "/proc/$PID/smaps" 2>/dev/null | grep "^[0-9a-f]" | head -20 | tee "$OUTDIR/large_anon_mmaps.txt" | wc -l)
echo "Total memory regions: $ANON_MMAP_COUNT" | tee "$OUTDIR/arena_count.txt"
echo "Anonymous regions with Resident pages: $LARGE_ANON (potential arenas)" | tee -a "$OUTDIR/arena_count.txt"
if command -v gdb &>/dev/null; then
  echo "[INFO] For precise arena count, run: gdb -p $PID -batch -ex 'info malloc' 2>/dev/null"
fi

echo ""
echo "--- C5. Valgrind / ASan Guidance ---"
BINARY_RESOLVED=""
if [ -n "$BINARY" ]; then
  BINARY_RESOLVED="$BINARY"
elif [ -f "/proc/$PID/exe" ]; then
  BINARY_RESOLVED=$(readlink "/proc/$PID/exe" 2>/dev/null || echo "")
fi
if [ -n "$BINARY_RESOLVED" ] && [ -x "$BINARY_RESOLVED" ]; then
  echo "[INFO] Binary detected: $BINARY_RESOLVED" | tee "$OUTDIR/valgrind_guide.txt"
  echo "  To run with valgrind memcheck:" >> "$OUTDIR/valgrind_guide.txt"
  echo "    valgrind --tool=memcheck --leak-check=full \\" >> "$OUTDIR/valgrind_guide.txt"
  echo "      --show-leak-kinds=all --log-file=$OUTDIR/valgrind.out \\" >> "$OUTDIR/valgrind_guide.txt"
  echo "      $BINARY_RESOLVED" >> "$OUTDIR/valgrind_guide.txt"
  echo "  To run with AddressSanitizer (recompile required):" >> "$OUTDIR/valgrind_guide.txt"
  echo "    gcc -fsanitize=address -g -o program program.c" >> "$OUTDIR/valgrind_guide.txt"
  echo "  To attach to running process with valgrind (gcore + offline):" >> "$OUTDIR/valgrind_guide.txt"
  echo "    gcore -o $OUTDIR/core $PID" >> "$OUTDIR/valgrind_guide.txt"
  echo "    valgrind --tool=memcheck --leak-check=full $BINARY_RESOLVED -c $OUTDIR/core" >> "$OUTDIR/valgrind_guide.txt"
else
  echo "[INFO] Binary not found. Run valgrind manually:" > "$OUTDIR/valgrind_guide.txt"
  echo "  valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all ./program" >> "$OUTDIR/valgrind_guide.txt"
fi
echo "[GUIDE] $OUTDIR/valgrind_guide.txt"

echo "==========================================="
echo "  Diagnosis Summary"
echo "  PID: $PID"
echo "  Complete output saved to: $OUTDIR"
