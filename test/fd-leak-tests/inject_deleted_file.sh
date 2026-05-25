#!/bin/bash
# ============================================================
# inject_deleted_file.sh — Branch G: 已删除文件 FD 泄漏
# 故障: 文件已 unlink 但进程仍持有 FD，磁盘空间不释放
# ============================================================
BIN_DIR="$HOME/fd-leak-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== 已删除文件 FD 泄漏 (Branch G) ==="
    echo "启动 leak_deleted_file..."
    pkill -f "leak_deleted_file" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/leak_deleted_file" > /tmp/leak_delf.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 5
    echo ""
    echo "=== 注入后状态 ==="
    cat /proc/sys/fs/file-nr | head -1
    echo ""
    echo "PID $PID 已删除但仍打开的 FD:"
    ls -la /proc/$PID/fd/ 2>/dev/null | grep '(deleted)' | head -10
    DEL_CNT=$(ls -la /proc/$PID/fd/ 2>/dev/null | grep -c '(deleted)' || true)
    echo "已删除但未关闭的 FD 数: $DEL_CNT"
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "我的 Linux 服务器上进程 PID $PID 持有已删除文件的文件描述符。lsof +L1 显示 link count=0。文件虽然已从目录树删除，但磁盘空间未释放。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== deleted_file 泄漏状态 ==="
    ps aux | grep leak_deleted_file | grep -v grep
    ;;
  stop)
    echo "停止 deleted_file 泄漏..."
    pkill -f "leak_deleted_file" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
