#!/bin/bash
# ============================================================
# inject_epoll.sh — Branch D: epoll FD 泄漏
# 故障: 创建 epoll 实例后不 close()
# ============================================================
BIN_DIR="$HOME/fd-leak-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== epoll FD 泄漏 (Branch D) ==="
    echo "启动 leak_epoll 2 30..."
    pkill -f "leak_epoll" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/leak_epoll" 2 30 > /tmp/leak_epoll.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 6
    echo ""
    echo "=== 注入后状态 ==="
    cat /proc/sys/fs/file-nr | head -1
    EP_COUNT=$(ls -la /proc/$PID/fd/ 2>/dev/null | grep -c eventpoll)
    echo "epoll FD 数: $EP_COUNT"
    ls -la /proc/$PID/fd/ 2>/dev/null | grep eventpoll | head -10
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "我的 Linux 服务器上发现进程 PID $PID 持有 $EP_COUNT 个 eventpoll FD，远超正常值。检查 /proc/$PID/fd/ 发现大量 anon_inode:[eventpoll]。怀疑 epoll 实例泄漏。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== epoll 泄漏状态 ==="
    ps aux | grep leak_epoll | grep -v grep
    PID=$(ps aux | grep leak_epoll | grep -v grep | awk '{print $2}' | head -1)
    [ -n "$PID" ] && echo "eventpoll FD: $(ls -la /proc/$PID/fd/ 2>/dev/null | grep -c eventpoll)" || echo "进程未运行"
    ;;
  stop)
    echo "停止 epoll 泄漏..."
    pkill -f "leak_epoll" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
