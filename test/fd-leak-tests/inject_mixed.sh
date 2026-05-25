#!/bin/bash
# ============================================================
# inject_mixed.sh — Branch H: 混合 FD 泄漏
# 故障: 同时泄漏 file + socket + epoll 三种 FD
# ============================================================
BIN_DIR="$HOME/fd-leak-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== 混合 FD 泄漏 (Branch H) ==="
    echo "启动 leak_mixed 3 30..."
    pkill -f "leak_mixed" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/leak_mixed" 3 30 > /tmp/leak_mixed.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 10
    echo ""
    echo "=== 注入后状态 ==="
    cat /proc/sys/fs/file-nr | head -1
    echo ""
    echo "PID $PID FD 类型分布:"
    ls -1 /proc/$PID/fd 2>/dev/null | while read f; do readlink "/proc/$PID/fd/$f" 2>/dev/null; done | sort | uniq -c | sort -rn
    TOTAL_FD=$(ls -1 /proc/$PID/fd 2>/dev/null | wc -l)
    echo ""
    echo "FD 总数: $TOTAL_FD"
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "我的 Linux 服务器上进程 PID $PID 出现混合 FD 泄漏。文件描述符总数已达 $TOTAL_FD 个，包含 regular file、socket、eventpoll 三种类型。系统 file-nr 偏高。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== mixed 泄漏状态 ==="
    ps aux | grep leak_mixed | grep -v grep
    ;;
  stop)
    echo "停止 mixed 泄漏..."
    pkill -f "leak_mixed" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
