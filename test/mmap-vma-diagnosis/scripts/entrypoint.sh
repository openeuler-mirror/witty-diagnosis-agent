#!/bin/bash
# entrypoint.sh — 故障注入验证测试入口
# 快速验证 3 个故障场景的诊断能力
set -e

echo "====================================================="
echo "  mmap-vma-diagnosis Skill — 故障注入验证测试"
echo "====================================================="
echo ""
echo "系统信息:"
uname -a
echo ""

DIAG="/skills/mmap-vma-diagnosis"
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')

# 设定测试环境
echo "--- 准备测试环境 ---"
echo 5000 > /proc/sys/vm/max_map_count
echo "max_map_count=$(cat /proc/sys/vm/max_map_count)"
echo ""

# ====================================================================
# 测试 1: max_map_count 耗尽 — 先启动故障，等它创建完映射再诊断
# ====================================================================
echo "╔══════════════════════════════════════════════╗"
echo "║  [测试1] vm.max_map_count 耗尽               ║"
echo "╚══════════════════════════════════════════════╝"

/test/fault_mmap_exhaust &
FPID=$!

# 等 fault 自己调整 max_map_count 后开始创建 VMA
echo "→ 等待故障进程触发 ENOMEM..."
for i in $(seq 1 25); do
    if ! kill -0 $FPID 2>/dev/null; then break; fi
    sleep 1
done

echo "→ 故障进程已结束（PID=$FPID），执行诊断..."
bash $DIAG/diagnose_mapcount.sh -S "$DATE_NOW" -p $FPID 2>&1
echo ""

# ====================================================================
# 测试 2: SIGBUS 文件截断
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试2] SIGBUS 文件截断"
echo "════════════════════════════════════════════════"

/test/fault_sigbus 2>&1 || true
echo ""

echo "→ 内核日志检查:"
dmesg 2>/dev/null | grep -iE "SIGBUS|bus error|segfault" | tail -5 || echo "  (无 SIGBUS 内核日志)"
echo "→ 运行 diagnose_sigbus.sh..."
bash $DIAG/diagnose_sigbus.sh -S "$DATE_NOW" 2>&1
echo ""

# ====================================================================
# 测试 3: mlock 超限 — 先降 memlock 限制再启动
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试3] mlock 超限"
echo "════════════════════════════════════════════════"

export MLOCK_LIMIT=4096  # 4KB — 小于 fault 要锁的 1MB
ulimit -l $MLOCK_LIMIT 2>/dev/null || true
echo "ulimit -l = $(ulimit -l)"

/test/fault_mlock_limit 2>&1
echo ""
echo "→ 运行 diagnose_mlock.sh..."
bash $DIAG/diagnose_mlock.sh -S "$DATE_NOW" 2>&1
echo ""

# ====================================================================
# 测试4: collect_vma_info
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试4] 系统级综合信息收集"
echo "════════════════════════════════════════════════"

bash $DIAG/collect_vma_info.sh -S "$DATE_NOW" 2>&1
echo ""

echo "====================================================="
echo "  全部测试完成！"
echo "====================================================="
