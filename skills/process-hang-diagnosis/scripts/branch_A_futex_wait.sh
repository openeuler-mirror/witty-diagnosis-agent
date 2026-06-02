#!/bin/bash
#
# 分支 A: futex 锁等待诊断
# 场景: 进程在 futex 上等待（普通锁竞争，非死锁）
# OS 特征: wchan=futex_wait_queue_me, State=S
#
# 用法: bash ./scripts/branch_A_futex_wait.sh <pid> [work_dir]

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
echo "===== 分支 A: futex 锁等待诊断 ====="
mkdir -p "$WORK_DIR/gdb_output"

# O1: 确认 OS 状态
echo ""
echo "--- O1: OS 状态确认 ---"
echo "State: $(cat /proc/$PID/status 2>/dev/null | grep "^State:" | awk '{print $2}')"
echo "wchan: $(cat /proc/$PID/wchan 2>/dev/null)"

# O2: 线程组 futex 等待情况
echo ""
echo "--- O2: 线程组 futex 分析 ---"
for t in /proc/$PID/task/*/; do
    tid=$(basename "$t")
    twchan=$(cat $t/wchan 2>/dev/null)
    tstate=$(cat $t/status 2>/dev/null | grep "^State:" | awk '{print $2}')
    echo "TID $tid: State=$tstate wchan=$twchan"
done

# O3: 调度时间统计
echo ""
echo "--- O3: 调度等待时间 ---"
cat /proc/$PID/sched 2>/dev/null | grep -E "wait_sum|nr_switches|nr_wakeups" || echo "(unavailable)"

# G0-G2: 内省分析（尝试 gdb）
echo ""
echo "--- G0-G2: 进程内省（gdb）---"
if command -v gdb &>/dev/null && kill -0 "$PID" 2>/dev/null; then
    echo "采集全线程栈..."
    gdb --batch -nx -ex "thread apply all bt" -p "$PID" 2>&1 | tee "$WORK_DIR/gdb_output/gdb_bt_all.txt" || \
        echo "[WARN] gdb attach 失败"
else
    echo "[SKIP] gdb 不可用或无权限 attach"
fi

# 输出摘要
echo ""
echo "===== 分支 A 诊断摘要 ====="
echo "进程 $PID 在 futex 上等待。"
echo '"OS 侧": futex 等待确认。'
echo '"内省侧": 若 gdb 成功，检查各线程 __lll_lock_wait 帧的 mutex 地址是否相同'
echo "        若所有线程等同一把锁 → 高竞争"
echo "        若不同线程等不同锁 → 检查是否形成等待环"
echo "建议: 若为高竞争，需优化锁粒度；若为异常等待，检查锁持有者状态"
