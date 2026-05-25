#!/bin/bash
# ============================================================
# inject_socketpair.sh — Fault G: socketpair 泄漏
# 故障: 进程每轮 socketpair() 调用后未 close 一端，
#       导致 anon_unix FD 持续泄漏
# 对应 skill 分支: branch_G_socketpair.sh
# ============================================================
BIN_DIR="$HOME/unix-pipe-test-lab/bin"
ACTION="${1:-run}"
PAIRS_PER_ROUND="${2:-10}"
ROUNDS="${3:-100}"

case "$ACTION" in
  run)
    echo "=== socketpair 泄漏 (Fault G) ==="
    pkill -f "socketpair_leak" 2>/dev/null; sleep 1
    echo "启动 socketpair_leak ${PAIRS_PER_ROUND} ${ROUNDS}..."
    nohup "$BIN_DIR/socketpair_leak" "$PAIRS_PER_ROUND" "$ROUNDS" > /tmp/socketpair_leak.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 5
    echo ""
    echo "=== 注入后状态 ==="
    echo "PID $PID FD 总数: $(ls -1 /proc/$PID/fd 2>/dev/null | wc -l)"
    echo "anon_unix FD 数: $(ls -la /proc/$PID/fd 2>/dev/null | grep "anon_inode:\[socketpair\]" | wc -l)"
    echo ""
    lsof -p $PID 2>/dev/null | grep "pipe\|UNIX" | head -10
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "检测到 socketpair 泄漏：进程 PID $PID 持续创建 socketpair 但未 close 一端，/proc/$PID/fd 中 anon_unix 类型 FD 持续增长。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== socketpair 泄漏状态 ==="
    ps aux | grep socketpair_leak | grep -v grep
    PID=$(pgrep -f "socketpair_leak" | head -1)
    if [ -n "$PID" ]; then
        echo "PID $PID FD 总数: $(ls -1 /proc/$PID/fd 2>/dev/null | wc -l)"
        echo "anon_unix: $(ls -la /proc/$PID/fd 2>/dev/null | grep "socketpair" | wc -l)"
    else
        echo "进程未运行"
    fi
    ;;
  stop)
    echo "停止 socketpair 泄漏注入..."
    pkill -f "socketpair_leak" 2>/dev/null; sleep 1; echo "已停止"
    rm -f /tmp/socketpair_leak.log 2>/dev/null
    ;;
  *)
    echo "用法: $0 [run|status|stop] [pairs_per_round] [rounds]"
    ;;
esac
