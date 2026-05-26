#!/bin/bash
# ============================================================
# inject_passcred.sh — Fault C: SO_PASSCRED 凭证传递失败
# 故障: 自动凭证机制 (SCM_CREDENTIALS) 因 receiver 未启用
#       SO_PASSCRED 而无法正确传递
# 对应 skill 分支: branch_C_passcred.sh
# ============================================================
BIN_DIR="$HOME/unix-pipe-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== SO_PASSCRED 凭证传递失败 (Fault C) ==="
    pkill -f "passcred_fail" 2>/dev/null; sleep 1
    echo "启动 sender (发送 SCM_CREDENTIALS)..."
    nohup "$BIN_DIR/passcred_fail" sender > /tmp/passcred_sender.log 2>&1 &
    PID_S=$!
    echo "Sender PID: $PID_S"
    echo "启动 receiver (未设置 SO_PASSCRED)..."
    nohup "$BIN_DIR/passcred_fail" receiver > /tmp/passcred_receiver.log 2>&1 &
    PID_R=$!
    echo "Receiver PID: $PID_R"
    sleep 3
    echo ""
    echo "=== 注入后状态 ==="
    echo "Sender 存活: $(kill -0 $PID_S 2>/dev/null && echo 是 || echo 否)"
    echo "Receiver 存活: $(kill -0 $PID_R 2>/dev/null && echo 是 || echo 否)"
    echo ""
    echo "--- Sender 日志 (尾) ---"
    tail -5 /tmp/passcred_sender.log 2>/dev/null
    echo ""
    echo "--- Receiver 日志 (尾) ---"
    tail -5 /tmp/passcred_receiver.log 2>/dev/null
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "检测到 Unix Domain Socket 凭证传递失败：sender PID $PID_S 发送 SCM_CREDENTIALS，但 receiver PID $PID_R 未设置 SO_PASSCRED 选项，凭证无法接收。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== passcred 状态 ==="
    ps aux | grep passcred_fail | grep -v grep
    echo "Sender: $(pgrep -f "passcred_fail" | head -1 || echo 未运行)"
    echo "Receiver: $(pgrep -f "passcred_fail" | tail -1 || echo 未运行)"
    ;;
  stop)
    echo "停止 passcred 注入..."
    pkill -f "passcred_fail" 2>/dev/null; sleep 1; echo "已停止"
    rm -f /tmp/passcred_*.log 2>/dev/null
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
