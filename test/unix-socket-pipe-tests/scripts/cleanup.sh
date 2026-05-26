#!/bin/bash
# ============================================================
# cleanup.sh — 停止所有 Unix Socket & Pipe 泄漏进程
# 用于 test/unix-socket-pipe-tests
# ============================================================
echo "=== 清理所有 Unix Socket & Pipe 泄漏进程 ==="
for proc in uds_backlog abstract_conflict passcred_fail socket_perms pipe_buf_full sigpipe_unhandled socketpair_leak; do
    pkill -f "$proc" 2>/dev/null && echo "  ✓ $proc 已停止" || true
done
sleep 1
echo ""
# Clean up socket / temp files
echo "清理临时 socket 和 pipe 文件..."
rm -f /tmp/uds_test_* 2>/dev/null
rm -f /tmp/test_uds_* 2>/dev/null
rm -f /tmp/uds_test_perms 2>/dev/null
echo ""
echo "检查残留 UDS 连接 (ss -xl 前 5 行):"
ss -xl | head -5
echo "..."
echo ""
echo "当前 file-nr:"
cat /proc/sys/fs/file-nr | head -1
echo ""
echo "检查残留泄漏进程:"
ps aux | grep -E "(uds_backlog|abstract_conflict|passcred_fail|socket_perms|pipe_buf_full|sigpipe_unhandled|socketpair_leak)" | grep -v grep && echo "(有残留)" || echo "(无)"
echo "=== 清理完成 ==="
