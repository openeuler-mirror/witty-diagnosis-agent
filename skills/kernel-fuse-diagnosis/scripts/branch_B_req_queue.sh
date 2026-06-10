#!/bin/bash
# branch_B_req_queue.sh — FUSE 请求队列阻塞诊断
# 场景: 操作卡死、进程 D 状态、waiting 持续增长
# 对应 SKILL.md Branch B
#
# Usage: bash branch_B_req_queue.sh [mount_point] [daemon_pid]

MOUNT_POINT="${1:-}"
DAEMON_PID="${2:-}"

echo "============================================"
echo " Branch B: FUSE 请求队列阻塞诊断"
echo "============================================"
echo ""

# ---- L2: 类型层诊断 ----

# 1. waiting 值
echo "--- [L2-1] 请求队列深度 (waiting) ---"
for conn in /sys/fs/fuse/connections/*/; do
    conn_id=$(basename "$conn")
    waiting=$(cat "$conn/waiting" 2>/dev/null)
    mb=$(cat "$conn/max_background" 2>/dev/null)
    echo "  连接 $conn_id: waiting=$waiting, max_background=$mb"
done
echo ""

# 2. D 状态进程
echo "--- [L2-2] D 状态进程 ---"
d_procs=$(ps aux | awk '$8 ~ /D/ {print}')
if [ -n "$d_procs" ]; then
    echo "  D 状态进程:"
    echo "$d_procs" | head -10
else
    echo "  无 D 状态进程"
fi
echo ""

# 3. D 状态进程内核栈（如果有）
echo "--- [L2-3] D 状态进程内核栈 ---"
for pid in $(ps aux | awk '$8 ~ /D/ {print $2}'); do
    echo "  PID $pid 内核栈:"
    cat /proc/$pid/stack 2>/dev/null || echo "    (无法读取)"
done
echo ""

# 4. strace daemon
if [ -n "$DAEMON_PID" ]; then
    echo "--- [L2-4] Daemon strace 采样 (10 秒) ---"
    timeout 10 strace -e trace=read,write,ioctl -p "$DAEMON_PID" -c 2>&1 || echo "  (strace 失败或无权限)"
    echo ""
fi

# 5. congested_threshold
echo "--- [L2-5] 拥塞阈值 ---"
for conn in /sys/fs/fuse/connections/*/; do
    conn_id=$(basename "$conn")
    ct=$(cat "$conn/congested_threshold_ms" 2>/dev/null)
    echo "  连接 $conn_id: congested_threshold_ms=$ct"
done
echo ""

# 6. 阻塞告警
echo "--- [L2-6] 内核 FUSE 阻塞告警 ---"
dmesg | grep -iE "fuse.*(block|congest|timeout)" | tail -10 2>/dev/null || echo "  (无阻塞告警)"
echo ""

# 7. 各连接详细状态
echo "--- [L2-7] 连接遍历详情 ---"
for conn in /sys/fs/fuse/connections/*/; do
    conn_id=$(basename "$conn")
    echo "  连接 $conn_id:"
    for attr in waiting max_background max_read abort congested_threshold_ms; do
        val=$(cat "$conn/$attr" 2>/dev/null || echo "N/A")
        echo "    $attr: $val"
    done
done
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

max_waiting=0
for conn in /sys/fs/fuse/connections/*/; do
    w=$(cat "$conn/waiting" 2>/dev/null)
    [ -n "$w" ] && [ "$w" -gt "$max_waiting" ] && max_waiting=$w
done

d_count=$(ps aux | awk '$8 ~ /D/ {count++} END {print count+0}')

if [ "$max_waiting" -gt 0 ]; then
    echo "  waiting 最大值: $max_waiting"
    echo "  D 状态进程数: $d_count"
    echo ""

    if [ "$max_waiting" -gt 100 ]; then
        echo "结论: 请求队列深度异常 (waiting=$max_waiting)，"
        echo "      有 $d_count 个 D 状态进程。"
        if [ -n "$DAEMON_PID" ]; then
            echo "根因: FUSE daemon 工作线程无法及时消费内核下发的请求。"
            echo "      可能原因: 线程池太小 / 后端 I/O 阻塞 / 死锁。"
        else
            echo "根因: 请求队列阻塞，可能 daemon 线程不足或后端 I/O 瓶颈。"
        fi
    elif [ "$max_waiting" -gt 10 ]; then
        echo "结论: 请求队列轻度堆积 (waiting=$max_waiting)，"
        echo "      需要观察增长趋势。"
        echo "根因: 可能存在瞬时请求高峰或轻微后端延迟。"
    else
        echo "结论: 队列深度正常，非队列阻塞问题。"
        echo "根因: 当前现象与队列阻塞不匹配，建议排查其他方向。"
    fi
else
    echo "结论: waiting=0，无请求队列堆积。"
    echo "根因: 当前无队列阻塞，建议排查其他故障类型。"
fi

echo ""
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
