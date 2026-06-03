#!/bin/bash
#
# 分支 G: 用户态死循环/空转诊断
# 场景: 进程 state=R 但不做有用功，CPU 占用高或低但进程无响应
# OS 特征: State=R, wchan 为空或周期性变化, 进程"假活真死"
#
# 用法: bash ./scripts/branch_G_user_loop.sh <pid> [work_dir]

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
echo "===== 分支 G: 用户态死循环/空转诊断 ====="
mkdir -p "$WORK_DIR/gdb_output"

# O1: 确认 OS 状态
echo ""
echo "--- O1: OS 状态确认 ---"
echo "State: $(cat /proc/$PID/status 2>/dev/null | grep "^State:" | awk '{print $2}')"
echo "wchan: $(cat /proc/$PID/wchan 2>/dev/null)"
echo "CPU 使用:"
ps -p "$PID" -o pid,%cpu,%mem,time 2>/dev/null || true

# O2: 调度时间
echo ""
echo "--- O2: 调度统计 ---"
cat /proc/$PID/sched 2>/dev/null | grep -E "wait_sum|nr_switches|nr_wakeups|sum_exec_runtime" || echo "(unavailable)"

# G6: gdb 连续采样（核心——判断是否为循环）
echo ""
echo "--- G6: GDB 连续栈采样（5次, 间隔0.5s）---"
if command -v gdb &>/dev/null && kill -0 "$PID" 2>/dev/null; then
    for i in {1..5}; do
        echo "=== Sample $i ($(date +%H:%M:%S.%N)) ==="
        gdb --batch -nx -ex "bt 20" -p "$PID" 2>&1
        sleep 0.5
    done | tee "$WORK_DIR/gdb_output/gdb_sampling.txt"
else
    echo "[SKIP] gdb 不可用或无权限"
fi

# perf 采样
echo ""
echo "--- perf 热点分析（可选）---"
if command -v perf &>/dev/null; then
    echo "perf top -p $PID (采样3秒)..."
    perf top -p "$PID" -s symbol -d 1 -n 10 2>&1 || \
        echo "[SKIP] perf 不可用或无权限"
else
    echo "[SKIP] perf 未安装"
fi

# 采样结果解读
echo ""
echo "===== 采样结果解读 ====="
echo "连续 5 次 bt 结果:"
echo "  完全一致 → 进程卡在同一个调用点（可能是死循环或阻塞在用户态）"
echo "  有微小变化 → 进程在运行但可能效率极低"
echo "  完全不同 → 进程正常运行，不属于 hang"
echo ""
echo "建议: 如果确认是死循环，使用 perf top 定位热点函数，然后检查对应源码循环条件"
