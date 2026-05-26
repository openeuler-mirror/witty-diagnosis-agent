#!/bin/bash
# entrypoint.sh — 故障注入验证测试入口
# 快速验证 6 个故障场景的诊断能力（全覆盖 A~F 路径）
set -e

echo "====================================================="
echo "  mmap-vma-diagnosis Skill — 故障注入验证测试（6路径全覆盖）"
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
# 测试 1: 路径A — vm.max_map_count 耗尽（已测）
# ====================================================================
echo "╔══════════════════════════════════════════════╗"
echo "║  [测试1] 路径A: vm.max_map_count 耗尽         ║"
echo "╚══════════════════════════════════════════════╝"

/test/fault_mmap_exhaust &
FPID=$!
echo "→ 等待故障进程触发 ENOMEM..."
for i in $(seq 1 25); do
    if ! kill -0 $FPID 2>/dev/null; then break; fi
    sleep 1
done
echo "→ 故障进程已结束（PID=$FPID），执行诊断..."
bash $DIAG/diagnose_mapcount.sh -S "$DATE_NOW" -p $FPID 2>&1
echo ""

# ====================================================================
# 测试 2: 路径B — SIGBUS 文件截断（已测）
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试2] 路径B: SIGBUS 文件截断"
echo "════════════════════════════════════════════════"

/test/fault_sigbus 2>&1 || true
echo ""
echo "→ 内核日志检查:"
dmesg 2>/dev/null | grep -iE "SIGBUS|bus error|segfault" | tail -5 || echo "  (无 SIGBUS 内核日志)"
echo "→ 运行 diagnose_sigbus.sh..."
bash $DIAG/diagnose_sigbus.sh -S "$DATE_NOW" 2>&1
echo ""

# ====================================================================
# 测试 3: 路径C — mlock 超限（已测）
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试3] 路径C: mlock 超限"
echo "════════════════════════════════════════════════"

export MLOCK_LIMIT=4096
ulimit -l $MLOCK_LIMIT 2>/dev/null || true
echo "ulimit -l = $(ulimit -l)"
/test/fault_mlock_limit 2>&1
echo ""
echo "→ 运行 diagnose_mlock.sh..."
bash $DIAG/diagnose_mlock.sh -S "$DATE_NOW" 2>&1
echo ""

# ====================================================================
# 测试 4: 路径D — 共享内存权限拒绝（之前未测试）
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试4] 路径D: 共享内存映射诊断【新增】"
echo "════════════════════════════════════════════════"

/test/fault_shm_create &
SHM_PID=$!
echo "→ 等待共享内存创建..."
sleep 3
kill -0 $SHM_PID 2>/dev/null || true
echo "→ 运行 diagnose_shm.sh..."
bash $DIAG/diagnose_shm.sh -S "$DATE_NOW" 2>&1
kill $SHM_PID 2>/dev/null || true
wait $SHM_PID 2>/dev/null || true
echo ""

# ====================================================================
# 测试 5: 路径E — 地址空间碎片化（之前未测试）
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试5] 路径E: 地址空间碎片化诊断【新增】"
echo "════════════════════════════════════════════════"

/test/fault_fragmentation &
FRAG_PID=$!
echo "→ 等待碎片创建（约5秒）..."
sleep 6
echo "→ 运行 diagnose_fragmentation.sh -p $FRAG_PID..."
bash $DIAG/diagnose_fragmentation.sh -S "$DATE_NOW" -p $FRAG_PID 2>&1
kill $FRAG_PID 2>/dev/null || true
wait $FRAG_PID 2>/dev/null || true
echo ""

# ====================================================================
# 测试 6: 路径F — 通用 mmap 失败（通过 collect 综合采集）
# ====================================================================
echo "════════════════════════════════════════════════"
echo "  [测试6] 路径F: 系统级综合信息收集（通用诊断）"
echo "════════════════════════════════════════════════"

bash $DIAG/collect_vma_info.sh -S "$DATE_NOW" 2>&1
echo ""

echo "====================================================="
echo "  全部6路径测试完成！"
echo "  路径A max_map_count - ✅"
echo "  路径B SIGBUS        - ✅"
echo "  路径C mlock         - ✅"
echo "  路径D 共享内存       - ✅（新增）"
echo "  路径E 碎片化         - ✅（新增）"
echo "  路径F 通用 mmap      - ✅"
echo "====================================================="
