#!/bin/bash
# ============================================================
# cleanup.sh — 停止所有 FD 泄漏进程
# 用于 test/fd-leak-tests
# ============================================================
echo "=== 清理所有 FD 泄漏进程 ==="
for proc in leak_system_fd leak_process_fd leak_close_wait leak_epoll leak_inotify leak_deleted_file leak_mixed; do
    pkill -f "$proc" 2>/dev/null && echo "  ✓ $proc 已停止" || true
done
sleep 1
echo ""
echo "最终 file-nr:"
cat /proc/sys/fs/file-nr | head -1
echo ""
echo "检查残留泄漏进程:"
ps aux | grep leak_ | grep -v grep && echo "(有残留)" || echo "(无)"
echo "=== 清理完成 ==="
