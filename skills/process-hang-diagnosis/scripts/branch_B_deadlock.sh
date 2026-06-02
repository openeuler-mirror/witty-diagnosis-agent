#!/bin/bash
#
# 分支 B: ABBA 死锁诊断
# 场景: 多线程相互等待锁，形成死锁环
# OS 特征: 多线程 wchan=futex_wait_queue_me
#
# 用法: bash ./scripts/branch_B_deadlock.sh <pid> [work_dir]

set -euo pipefail

# CMD_PREFIX: 命令执行前缀，容器诊断时设置为 "docker exec <容器名>"
# 示例: CMD_PREFIX="docker exec process-hang-branch-g" bash 01_baseline_info.sh 1
: "${CMD_PREFIX:=}"

# run() — 通过 CMD_PREFIX 执行命令
run() {
  if [ -n "$CMD_PREFIX" ]; then
    $CMD_PREFIX "$@"
  else
    "$@"
  fi
}


PID="${1:?Usage: $0 <pid> [work_dir]}"
WORK_DIR="${2:-./hang_diag_${PID}}"
echo "===== 分支 B: ABBA 死锁诊断 ====="
mkdir -p "$WORK_DIR/gdb_output"

# O1: 确认线程组状态
echo ""
echo "--- O1: 线程组状态 ---"
thread_count=0
for t in /proc/$PID/task/*/; do
    thread_count=$((thread_count + 1))
    tid=$(basename "$t")
    twchan=$(cat $t/wchan 2>/dev/null)
    echo "TID $tid wchan=$twchan"
done
echo "线程总数: $thread_count"

if [ "$thread_count" -lt 2 ]; then
    echo "[ NOTE] 单线程进程不太可能 ABBA 死锁"
    echo " (除非是同一线程递归申请互斥锁，见 references/lock_analysis_patterns.md 模式5)"
fi

# O2: 全系统同类 wchan 进程
echo ""
echo "--- O2: 全系统 futex 等待进程 ---"
ps -eo pid,wchan,comm --no-headers 2>/dev/null | grep -E "futex" || echo "(无其他 futex 等待进程)"

# G1-G2: gdb 全线程栈（核心证据）
echo ""
echo "--- G1-G2: 全线程栈采集（死锁关键证据）---"
if command -v gdb &>/dev/null && kill -0 "$PID" 2>/dev/null; then
    gdb --batch -nx -ex "thread apply all bt full" -p "$PID" 2>&1 | tee "$WORK_DIR/gdb_output/gdb_deadlock_bt.txt" || \
        echo "[WARN] gdb attach 失败"

    echo ""
    echo "--- G2: 死锁模式检测 ---"
    echo "手动检查输出中的锁地址模式："
    echo "1. 寻找 __pthread_mutex_lock (mutex=0x...) 帧"
    echo "2. 对比各线程的 mutex 地址"
    echo "3. 匹配模式："
    echo "   Thread A: mutex=0xL2 (等 L2) 但持有了 L1"
    echo "   Thread B: mutex=0xL1 (等 L1) 但持有了 L2"
    echo "   ───> ABBA 死锁确认"
    echo ""
    echo "检查以上输出中的 __lll_lock_wait 帧前后的 mutex 地址即可确认"
else
    echo "[SKIP] gdb 不可用或无权限 attach"
    echo "无 gdb 时只能基于 wchan 推断，置信度降级"
fi

# 输出摘要
echo ""
echo "===== 分支 B 诊断摘要 ====="
echo "进程 $PID 线程数 $thread_count"
echo "OS 侧: 多线程 futex 等待（死锁可疑）"
echo "内省侧: 见 gdb 输出，确认是否 ABBA 模式"
