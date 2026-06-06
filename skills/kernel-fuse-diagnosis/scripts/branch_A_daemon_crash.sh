#!/bin/bash
# branch_A_daemon_crash.sh — FUSE Daemon 崩溃/EIO 诊断
# 场景: stat/ls 返回 "Transport endpoint is not connected" 或 EIO
# 对应 SKILL.md Branch A
#
# Usage: bash branch_A_daemon_crash.sh <mount_point> [daemon_name]

MOUNT_POINT="${1:?错误: 需要挂载点路径作为第一个参数}"
DAEMON_NAME="${2:-}"

echo "============================================"
echo " Branch A: FUSE Daemon 崩溃/EIO 诊断"
echo "============================================"
echo "  挂载点: $MOUNT_POINT"
echo "  Daemon: ${DAEMON_NAME:-未指定}"
echo ""

# ---- L2: 类型层诊断 ----

# 1. stat 确认错误码
echo "--- [L2-1] stat 挂载点 ---"
stat "$MOUNT_POINT" 2>&1
echo ""

# 2. 检查 /proc/mounts
echo "--- [L2-2] /proc/mounts 中的挂载条目 ---"
grep "$MOUNT_POINT" /proc/mounts 2>/dev/null || echo "  (挂载条目不存在)"
echo ""

# 3. sysfs 连接状态
echo "--- [L2-3] FUSE 连接状态 (sysfs) ---"
conns=$(ls /sys/fs/fuse/connections/ 2>/dev/null)
if [ -n "$conns" ]; then
    for conn in $conns; do
        echo "  连接 ID: $conn"
        echo "    abort:  $(cat /sys/fs/fuse/connections/$conn/abort 2>/dev/null || echo N/A)"
        echo "    waiting: $(cat /sys/fs/fuse/connections/$conn/waiting 2>/dev/null || echo N/A)"
    done
else
    echo "  (无活跃连接 — 连接已销毁)"
fi
echo ""

# 4. daemon 进程
echo "--- [L2-4] Daemon 进程检查 ---"
if [ -n "$DAEMON_NAME" ]; then
    pids=$(pgrep -f "$DAEMON_NAME" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "  Daemon 进程存在: PID(s) $pids"
        ps -p $pids -o pid,stat,etime,cmd 2>/dev/null
    else
        echo "  Daemon 进程: 不存在 (已崩溃/退出)"
    fi
else
    fuse_procs=$(ps aux | grep -E "[f]use" 2>/dev/null)
    if [ -n "$fuse_procs" ]; then
        echo "  FUSE 相关进程:"
        echo "$fuse_procs"
    else
        echo "  无 FUSE 进程运行"
    fi
fi
echo ""

# 5. daemon 日志
echo "--- [L2-5] Daemon 退出日志 ---"
if [ -n "$DAEMON_NAME" ]; then
    journalctl -u "$DAEMON_NAME" --since "10 min ago" --no-pager 2>/dev/null | tail -20 || echo "  (journalctl 不可用或无服务)"
fi
echo ""

# 6. dmesg
echo "--- [L2-6] 内核 FUSE 消息 ---"
dmesg | grep -iE "fuse|libfuse" | tail -20 2>/dev/null || echo "  (dmesg 不可用或无消息)"
echo ""

# 7. OOM Killer 检查
echo "--- [L2-7] OOM Killer 检查 ---"
dmesg | grep -i "oom-killer" | tail -5 2>/dev/null || echo "  (无 OOM Killer 记录)"
if [ -n "$DAEMON_NAME" ]; then
    dmesg | grep -i "Killed process" | grep -i "$DAEMON_NAME" | tail -5 2>/dev/null || echo "  (无匹配的 killed 记录)"
fi
echo ""

# 8. abort 状态
echo "--- [L2-8] abort 状态 ---"
for conn in $conns; do
    abort_val=$(cat /sys/fs/fuse/connections/$conn/abort 2>/dev/null)
    echo "  连接 $conn abort=$abort_val"
done
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

# 判定逻辑
has_conns=$( [ -n "$conns" ] && echo 1 || echo 0 )
has_daemon=$( [ -n "$(pgrep -f "$DAEMON_NAME" 2>/dev/null)" ] && echo 1 || echo 0 )
if [ -z "$DAEMON_NAME" ]; then
    has_daemon=2  # 未知
fi
has_oom=$( dmesg 2>/dev/null | grep -i "Killed process" | grep -i "${DAEMON_NAME:-fuse}" | wc -l )

if [ "$has_conns" -eq 0 ] && [ "$has_daemon" -eq 0 ]; then
    echo "结论: FUSE daemon 进程不存在（已崩溃），"
    echo "      /sys/fs/fuse/connections/ 目录为空（连接已销毁）。"
    if [ "$has_oom" -gt 0 ]; then
        echo "      OOM Killer 记录了 daemon 被终止。"
        echo "根因: FUSE daemon 因内存超限被 OOM Killer 杀死。"
    else
        echo "根因: FUSE daemon 程序异常退出（可能 SIGSEGV/SIGABRT/exit）。"
        echo "      建议检查 daemon 进程退出码和日志。"
    fi
elif [ "$has_conns" -eq 0 ] && [ "$has_daemon" -eq 1 ]; then
    echo "结论: Daemon 进程存在但连接已销毁，"
    echo "      可能 daemon 重启后未重新挂载。"
    echo "根因: Daemon 进程重启但 FUSE 文件系统未重新挂载。"
elif [ "$has_conns" -eq 1 ] && [ "$has_daemon" -eq 0 ]; then
    echo "结论: Daemon 进程不存在但连接仍在，"
    echo "      连接处于残留状态（等待超时回收）。"
    echo "根因: Daemon 退出后连接未及时清理。"
elif [ "$has_conns" -eq 1 ] && [ "$has_daemon" -eq 1 ]; then
    echo "结论: Daemon 进程存在且连接存在，但操作返回 EIO。"
    echo "      可能 daemon 内部状态机异常或连接已 abort。"
    abort_val=$(cat /sys/fs/fuse/connections/*/abort 2>/dev/null)
    if [ "$abort_val" = "1" ]; then
        echo "根因: 连接已被主动 abort（daemon 调用 fuse_abort 或内核中止）。"
    else
        echo "根因: Daemon 内部状态异常，需检查 daemon 日志和内核栈。"
    fi
else
    echo "结论: 无法确定具体状态，建议检查 dmesg 和 daemon 日志。"
fi

echo ""
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
