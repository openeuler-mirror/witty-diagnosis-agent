#!/bin/bash
# ============================================================
# inject_process_fd.sh — Branch B: 进程级 FD 泄漏
# 故障: 进程缓慢泄漏 regular file FD
# 对应 skill 分支: branch_B_process_fd.sh
# ============================================================
BIN_DIR="$HOME/fd-leak-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== 进程级 FD 泄漏 (Branch B) ==="
    echo "启动 leak_process_fd 1 50 (每秒1个FD, 上限50)..."
    pkill -f "leak_process_fd" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/leak_process_fd" 1 50 > /tmp/leak_procfd.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 5
    echo ""
    echo "=== 注入后状态 ==="
    cat /proc/sys/fs/file-nr | head -1
    echo "PID $PID FD 数: $(ls -1 /proc/$PID/fd 2>/dev/null | wc -l)"
    ls -la /proc/$PID/fd/ 2>/dev/null | grep "/tmp/leak_fd" | head -5
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "我的 Linux 服务器上一个进程（PID $PID）文件描述符持续增长，检查 /proc/$PID/fd/ 发现大量 /tmp/leak_fd_* 文件句柄。怀疑 FD 泄漏。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== process_fd 泄漏状态 ==="
    ps aux | grep leak_process_fd | grep -v grep
    PID=$(ps aux | grep leak_process_fd | grep -v grep | awk '{print $2}' | head -1)
    [ -n "$PID" ] && echo "FD 数: $(ls -1 /proc/$PID/fd 2>/dev/null | wc -l)" || echo "进程未运行"
    ;;
  stop)
    echo "停止 process_fd 泄漏..." 
    pkill -f "leak_process_fd" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
