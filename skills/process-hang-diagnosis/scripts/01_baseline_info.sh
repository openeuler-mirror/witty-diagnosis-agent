#!/bin/bash
#
# 进程挂起基线信息采集 + 分支推荐
# 用法: bash ./scripts/01_baseline_info.sh <pid> [work_dir]
#
# 输出:
#   - 终端打印进程状态摘要 + 推荐分支
#   - 工作目录下保存 procfs 快照

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
WORK_DIR="${2:-./hang_diag_${PID}_$(date +%Y%m%d%H%M%S)}"
mkdir -p "$WORK_DIR/proc"
mkdir -p "$WORK_DIR/sys"

echo "========================================"
echo " 进程挂起基线信息采集"
echo " PID: $PID"
echo " 工作目录: $WORK_DIR"
echo " 时间: $(date)"
echo "========================================"

# 1. 检查 PID 是否存在
if ! kill -0 "$PID" 2>/dev/null; then
    echo "[ERROR] PID $PID 不存在或权限不足"
    exit 1
fi

# 2. 进程基本信息
echo ""
echo "--- 1/6 进程基本信息 ---"
cat /proc/$PID/status > "$WORK_DIR/proc/status" 2>/dev/null || true
cat /proc/$PID/status 2>/dev/null | grep -E "^Name|^State|^Tgid|^Pid|^PPid|^Threads|^Sig" || \
    echo "[WARN] 无法读取 /proc/$PID/status (可能权限不足)"

# 3. 内核级等待状态
echo ""
echo "--- 2/6 内核等待状态 ---"
echo -n "wchan: "
cat /proc/$PID/wchan > "$WORK_DIR/proc/wchan" 2>/dev/null || echo "(unavailable)"
cat /proc/$PID/wchan 2>/dev/null || echo "(unavailable)"

echo ""
echo "kernel stack:"
cat /proc/$PID/stack > "$WORK_DIR/proc/stack" 2>/dev/null || echo "(unavailable)"
cat /proc/$PID/stack 2>/dev/null || echo "(unavailable)"

if [ -f /proc/$PID/syscall ]; then
    echo ""
    echo "current syscall:"
    cat /proc/$PID/syscall > "$WORK_DIR/proc/syscall" 2>/dev/null || true
    cat /proc/$PID/syscall 2>/dev/null || true
fi

# 调度统计
echo ""
echo "sched:"
cat /proc/$PID/sched > "$WORK_DIR/proc/sched" 2>/dev/null || true
cat /proc/$PID/sched 2>/dev/null | head -15 || echo "(unavailable)"

# 4. 线程组信息
echo ""
echo "--- 3/6 线程组信息 ---"
echo "线程列表:"
for t in /proc/$PID/task/*/; do
    tid=$(basename "$t")
    name=$(cat $t/status 2>/dev/null | grep "^Name:" | awk '{print $2}') || name="?"
    state=$(cat $t/status 2>/dev/null | grep "^State:" | awk '{print $2}') || state="?"
    twchan=$(cat $t/wchan 2>/dev/null) || twchan="?"
    echo "  TID $tid ($name) State=$state wchan=$twchan"
done

# 5. 进程资源
echo ""
echo "--- 4/6 文件描述符 ---"
# 文件描述符列表直接保存到 proc/fd_list
ls -la /proc/$PID/fd/ > "$WORK_DIR/proc/fd_list" 2>/dev/null || true
ls -la /proc/$PID/fd/ 2>/dev/null | head -30 || echo "(无法读取 fd)"

echo ""
echo "--- 5/6 资源限制与 IO ---"
cat /proc/$PID/limits > "$WORK_DIR/proc/limits" 2>/dev/null || true
cat /proc/$PID/io > "$WORK_DIR/proc/io" 2>/dev/null || true
echo "limits & IO saved."

# 进程内存映射
echo ""
echo "--- 5b/6 内存映射 ---"
cat /proc/$PID/maps > "$WORK_DIR/proc/maps" 2>/dev/null || true
echo "maps saved."

# 6. 系统级竞争证据
echo ""
echo "--- 6/6 系统级锁和同类阻塞进程 ---"
# /proc/locks
cat /proc/locks > "$WORK_DIR/sys/locks" 2>/dev/null || true
echo "/proc/locks saved."

# 同类 wchan 进程
wchan_val=$(cat /proc/$PID/wchan 2>/dev/null)
if [ -n "$wchan_val" ]; then
    echo ""
    echo "同 wchan ($wchan_val) 的进程:"
    ps -eo pid,wchan,comm --no-headers 2>/dev/null | awk -v w="$wchan_val" '$2==w {print "  PID=" $1 " comm=" $3}' | head -10
fi

# ========================================
# 分支推荐逻辑
# ========================================
echo ""
echo "========================================"
echo " 分支推荐"
echo "========================================"

STATE=$(cat /proc/$PID/status 2>/dev/null | grep "^State:" | awk '{print $2}' || echo "?")
WCHAN=$(cat /proc/$PID/wchan 2>/dev/null || echo "?")

recommendations=""

if [ "$STATE" = "T" ] || [ "$STATE" = "t" ]; then
    recommendations="$recommendations branch_E_signal_stop (状态 T/t — 信号停止/跟踪)"
fi

if [ "$WCHAN" = "futex_wait_queue_me" ]; then
    # 进一步区分是普通 futex 等待还是死锁
    thread_count=$(ls -d /proc/$PID/task/*/ 2>/dev/null | wc -l)
    if [ "$thread_count" -ge 2 ]; then
        recommendations="$recommendations branch_B_deadlock (多线程 + wchan=futex — 怀疑死锁)"
    else
        recommendations="$recommendations branch_A_futex_wait (单线程 wchan=futex — futex 锁等待)"
    fi
fi

if echo "$WCHAN" | grep -qE "pipe_read|pipe_write|sock_|tcp_|unix_"; then
    recommendations="$recommendations branch_D_pipe_socket (wchan 含 pipe/socket — 管道/Socket 阻塞)"
fi

if [ "$STATE" = "D" ]; then
    recommendations="$recommendations branch_F_d_state (State=D — D状态不可中断阻塞)"
fi

if grep -q "$PID" /proc/locks 2>/dev/null; then
    recommendations="$recommendations branch_C_filelock (/proc/locks 含本进程 — 文件锁竞争)"
fi

# 若没有触发任何分支，但有 wchan
if [ -z "$recommendations" ] && [ "$STATE" = "R" ]; then
    recommendations="$recommendations branch_G_user_loop (State=R 但不做功 — 用户态死循环)"
fi

if [ -z "$recommendations" ]; then
    recommendations="  (无显著异常分支匹配，建议查看完整日志手动分析)"
fi

echo "$recommendations"

echo ""
echo "基线信息已保存到: $WORK_DIR"
echo "推荐分支: $recommendations" | head -1
