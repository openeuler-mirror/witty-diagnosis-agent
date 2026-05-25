#!/bin/bash
# ============================================================
# inject_inotify.sh — Branch E: inotify watch 泄漏
# 故障: 添加文件监控 watch 后不 rm_watch()
# ============================================================
BIN_DIR="$HOME/fd-leak-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== inotify watch 泄漏 (Branch E) ==="
    echo "启动 leak_inotify 1 60..."
    pkill -f "leak_inotify" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/leak_inotify" 1 60 > /tmp/leak_inotify.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 8
    echo ""
    echo "=== 注入后状态 ==="
    cat /proc/sys/fs/file-nr | head -1
    INO_FD=$(ls -la /proc/$PID/fd/ 2>/dev/null | grep inotify | head -1 | awk '{print $NF}')
    echo "inotify FD: $INO_FD"
    if [ -n "$INO_FD" ]; then
        INO_FD_NUM=$(echo "$INO_FD" | grep -oP '\d+$' || echo "")
        [ -n "$INO_FD_NUM" ] && cat /proc/$PID/fdinfo/$INO_FD_NUM 2>/dev/null | head -5 || echo "(fdinfo 不可读)"
    fi
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "我的 Linux 服务器上进程 PID $PID 的 inotify watch 数量异常增长。怀疑 inotify watch 泄漏，可能导致 ENOSPC 错误。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== inotify 泄漏状态 ==="
    ps aux | grep leak_inotify | grep -v grep
    ;;
  stop)
    echo "停止 inotify 泄漏..."
    pkill -f "leak_inotify" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
