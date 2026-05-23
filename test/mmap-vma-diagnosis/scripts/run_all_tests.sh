#!/bin/bash
# run_all_tests.sh — 一次性运行两个测试，确保输出不丢失
set -e

OUTDIR="/tmp/test_output"
mkdir -p "$OUTDIR"
SUMMARY="$OUTDIR/summary.txt"
> "$SUMMARY"

echo "================================================"
echo "  mmap-vma-diagnosis — 故障注入验证测试"
echo "  日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"
echo ""

echo "=== 测试1: vm.max_map_count 耗尽 ==="
echo 300 > /proc/sys/vm/max_map_count
echo "max_map_count=$(cat /proc/sys/vm/max_map_count)"
echo ""

# 后台启动故障注入
/test/fault_mmap_exhaust &
FPID=$!
echo "故障进程PID=$FPID，等待5秒让 mmap 创建并触发 ENOMEM..."

# 等待故障进程触发 ENOMEM 并进入 pause
sleep 5

# 检查进程是否仍在运行（应在 pause 60s 阶段）
if kill -0 $FPID 2>/dev/null; then
    echo "进程仍在运行（pause阶段），执行诊断..."
    echo ""
    bash /skills/mmap-vma-diagnosis/diagnose_mapcount.sh -S "2026-05-19 00:00:00" -p $FPID 2>&1
else
    echo "进程已结束，执行离线诊断..."
    bash /skills/mmap-vma-diagnosis/diagnose_mapcount.sh -S "2026-05-19 00:00:00" 2>&1
fi

# 终止故障进程（释放 mmap 资源）
kill $FPID 2>/dev/null || true
wait $FPID 2>/dev/null || true
echo ""
echo "--- 测试1 完成 ---"
echo ""

echo "=== 测试2: SIGBUS 文件截断 ==="
echo ""
/test/fault_sigbus 2>&1 || true
echo ""
echo "=== strace 确认信号 ==="
strace -e trace=mmap,ftruncate,msync -f /test/fault_sigbus 2>&1 | grep -E "SIGBUS|si_signo=7|BUS_ADRERR" | head -5 || true
echo ""
echo "=== dmesg 内核日志 ==="
dmesg 2>/dev/null | grep -iE "SIGBUS|bus error|segfault" | tail -5 || echo "(容器内 dmesg 不可见)"
echo ""

echo "=== 运行诊断: diagnose_sigbus.sh ==="
bash /skills/mmap-vma-diagnosis/diagnose_sigbus.sh -S "2026-05-19" 2>&1
echo ""
echo "--- 测试2 完成 ---"
echo ""

echo "================================================"
echo "  全部测试完成"
echo "================================================"
