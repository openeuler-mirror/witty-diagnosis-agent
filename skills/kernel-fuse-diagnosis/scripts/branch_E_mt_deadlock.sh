#!/bin/bash
# branch_E_mt_deadlock.sh — FUSE 多线程 Daemon 死锁诊断
# 场景: daemon 进程存在但操作挂起，所有线程阻塞
# 对应 SKILL.md Branch E
#
# Usage: bash branch_E_mt_deadlock.sh <daemon_pid> [daemon_name]

DAEMON_PID="${1:?错误: 需要 Daemon PID 作为第一个参数}"
DAEMON_NAME="${2:-}"

echo "============================================"
echo " Branch E: 多线程 FUSE Daemon 死锁诊断"
echo "============================================"
echo "  PID: $DAEMON_PID"
echo "  名称: ${DAEMON_NAME:-未知}"
echo ""

# ---- L2: 类型层诊断 ----

# 1. 线程列表
echo "--- [L2-1] 线程列表 ---"
ps -eLf | awk -v pid="$DAEMON_PID" '$2 == pid || $3 == pid' | head -20 || \
    ps -eLf | head -1; ps -eLf | grep "$DAEMON_PID"
echo ""

# 2. 主线程内核栈
echo "--- [L2-2] 主线程内核栈 (PID $DAEMON_PID) ---"
cat /proc/$DAEMON_PID/stack 2>/dev/null || echo "  (无法读取)"
echo ""

# 3. 所有线程内核栈
echo "--- [L2-3] 所有线程内核栈 ---"
if [ -d "/proc/$DAEMON_PID/task" ]; then
    for tid in /proc/$DAEMON_PID/task/*/; do
        tid_num=$(basename "$tid")
        tid_status=$(cat "$tid/status" 2>/dev/null | head -3 | tr '\n' ' ')
        echo "  TID $tid_num: $tid_status"
        cat "$tid/stack" 2>/dev/null | sed 's/^/    /'
        echo ""
    done
else
    echo "  (/proc/$DAEMON_PID/task 不可访问)"
fi

# 4. strace 多线程追踪
echo "--- [L2-4] strace 多线程追踪 (5 秒) ---"
timeout 5 strace -f -e trace=write,read,ioctl -p "$DAEMON_PID" -c 2>&1 || echo "  (strace 失败或无权限)"
echo ""

# 5. GDB 全线程回溯（如果 gdb 可用）
echo "--- [L2-5] GDB 全线程回溯 ---"
if command -v gdb &>/dev/null; then
    gdb -p "$DAEMON_PID" -batch \
        -ex "thread apply all bt" \
        -ex "info threads" \
        -ex "quit" 2>&1 | head -80
else
    echo "  (gdb 未安装)"
fi
echo ""

# 6. waiting 值确认
echo "--- [L2-6] 请求队列深度 ---"
for conn in /sys/fs/fuse/connections/*/; do
    conn_id=$(basename "$conn")
    waiting=$(cat "$conn/waiting" 2>/dev/null)
    echo "  连接 $conn_id: waiting=$waiting"
done
echo ""

# 7. 信号检查
echo "--- [L2-7] 信号信息 ---"
cat /proc/$DAEMON_PID/status 2>/dev/null | grep -E "^(Sig|State|Name)" || echo "  (无法读取)"
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

# 检查线程状态
thread_count=0
blocked_threads=0
mutex_wait=0

if [ -d "/proc/$DAEMON_PID/task" ]; then
    for tid in /proc/$DAEMON_PID/task/*/; do
        thread_count=$((thread_count+1))
        state=$(cat "$tid/status" 2>/dev/null | grep "State:" | awk '{print $2}')
        [ "$state" = "S" ] || [ "$state" = "D" ] && blocked_threads=$((blocked_threads+1))
        stack=$(cat "$tid/stack" 2>/dev/null)
        if echo "$stack" | grep -q "mutex\|futex\|pthread_mutex_lock"; then
            mutex_wait=$((mutex_wait+1))
        fi
    done
fi

echo "  线程数: $thread_count"
echo "  阻塞线程: $blocked_threads"
echo "  等待互斥锁: $mutex_wait"

if [ "$blocked_threads" -gt 0 ]; then
    echo ""
    if [ "$mutex_wait" -ge 2 ]; then
        echo "结论: $mutex_wait 个线程在互斥锁等待中，可能有死锁。"
        echo "根因: FUSE daemon 多线程锁获取顺序不一致，导致经典 ABBA 死锁。"
        echo "      建议通过 gdb 全线程回溯分析锁依赖关系。"
    else
        echo "结论: $blocked_threads 个线程处于阻塞状态。"
        echo "根因: 线程阻塞可能由于后端 I/O 或锁等待，需进一步 gdb 分析。"
    fi
else
    echo "结论: 当前未检测到明显死锁迹象。"
    echo "根因: 非多线程死锁问题，建议排查其他故障类型。"
fi

echo ""
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
