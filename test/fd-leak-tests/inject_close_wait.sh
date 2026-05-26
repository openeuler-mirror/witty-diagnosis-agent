#!/bin/bash
# ============================================================
# inject_close_wait.sh — Branch C: CLOSE_WAIT Socket 泄漏
# 故障: 对端关闭连接后本端不 close()，CLOSE_WAIT 堆积
# ============================================================
BIN_DIR="$HOME/fd-leak-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== CLOSE_WAIT Socket 泄漏 (Branch C) ==="
    echo "启动 leak_close_wait 2 60..."
    pkill -f "leak_close_wait" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/leak_close_wait" 2 60 > /tmp/leak_cw.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 8
    echo ""
    echo "=== 注入后状态 ==="
    cat /proc/sys/fs/file-nr | head -1
    echo ""
    ss -tn state close-wait 2>/dev/null | tail -n +2 | head -10
    CW_COUNT=$(ss -tn state close-wait 2>/dev/null | tail -n +2 | wc -l)
    echo "CLOSE_WAIT 数量: $CW_COUNT"
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "我的 Linux 服务器出现大量 CLOSE_WAIT 连接（约 $CW_COUNT 个），进程 PID $PID 的 socket 持续堆积。ss -tn 显示大量连接处于 CLOSE_WAIT 状态。怀疑是应用程序未正确关闭对端已断开的连接。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== close_wait 泄漏状态 ==="
    ps aux | grep leak_close_wait | grep -v grep
    echo "CLOSE_WAIT: $(ss -tn state close-wait 2>/dev/null | tail -n +2 | wc -l)"
    ;;
  stop)
    echo "停止 close_wait 泄漏..."
    pkill -f "leak_close_wait" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
