#!/bin/bash
# entrypoint.sh — 自动运行所有故障注入测试
set -e

echo "================================================"
echo "  Page Cache / Reclaim Diagnosis — Fault Injection Tests"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"
echo ""

echo "=== Test 1: Dirty Page Writeback Storm ==="
/test/fault_dirty_storm 2>&1 || true
echo ""
echo "=== Test done ==="
echo ""

echo "=== Test 2: Drop Caches + IO Storm ==="
/test/fault_drop_caches 2>&1 || true
echo ""
echo "=== Test done ==="
echo ""

echo "=== Test 3: Reclaim Pressure (short) ==="
bash /test/fault_reclaim_pressure.sh 30 200 2>&1 || true
echo ""
echo "=== Test done ==="
echo ""

echo "================================================"
echo "  All tests completed"
echo "================================================"
