#!/bin/bash
# ============================================================
# inject_sigpipe.sh — Fault F: SIGPIPE 信号未处理
# 故障: 进程持续向已关闭的管道/socket 对端写入数据，
#       因未捕获 SIGPIPE 信号而被默认终止
# 对应 skill 分支: branch_F_sigpipe.sh
# ============================================================
BIN_DIR="$HOME/unix-pipe-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== SIGPIPE 信号未处理 (Fault F) ==="
    pkill -f "sigpipe_unhandled" 2>/dev/null; sleep 1
    echo "启动 sigpipe_unhandled 写入已关闭管道对端..."
    nohup "$BIN_DIR/sigpipe_unhandled" > /tmp/sigpipe.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 3
    echo ""
    echo "=== 注入后状态 ==="
    if kill -0 $PID 2>/dev/null; then
        echo "进程 PID $PID 仍存活（SIGPIPE 可能被捕获处理）"
    else
        echo "进程 PID $PID 已退出（预期行为：SIGPIPE 默认终止）"
        echo "退出信息:"
        wait $PID 2>/dev/null
        echo "退出码: $?"
    fi
    echo ""
    echo "--- 日志 (尾) ---"
    tail -10 /tmp/sigpipe.log 2>/dev/null
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "检测到 SIGPIPE 信号场景：进程 PID $PID 向已关闭的管道/socket 对端写入数据，预期因 SIGPIPE 默认处理而退出。日志内容见 /tmp/sigpipe.log。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== sigpipe 状态 ==="
    if pgrep -f "sigpipe_unhandled" > /dev/null 2>&1; then
        echo "进程运行中（SIGPIPE 已被自定义处理）"
        pgrep -f "sigpipe_unhandled"
    else
        echo "进程未运行（SIGPIPE 默认终止后未自动重启）"
    fi
    echo "日志文件尾:"
    tail -5 /tmp/sigpipe.log 2>/dev/null || echo "  (无日志)"
    ;;
  stop)
    echo "停止 sigpipe 注入..."
    pkill -f "sigpipe_unhandled" 2>/dev/null; sleep 1; echo "已停止"
    rm -f /tmp/sigpipe.log 2>/dev/null
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
