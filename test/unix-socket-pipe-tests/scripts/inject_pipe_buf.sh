#!/bin/bash
# ============================================================
# inject_pipe_buf.sh — Fault E: 管道缓冲区满写阻塞
# 故障: writer 高速写入管道，reader 读取过慢，
#       管道缓冲区（默认 64KB）被填满，writer 陷入 D 状态
# 对应 skill 分支: branch_E_pipe_buf.sh
# ============================================================
BIN_DIR="$HOME/unix-pipe-test-lab/bin"
ACTION="${1:-run}"
PIPE_SIZE_KB="${2:-64}"
WRITER_SPEED_KBPS="${3:-1024}"

case "$ACTION" in
  run)
    echo "=== 管道缓冲区满写阻塞 (Fault E) ==="
    pkill -f "pipe_buf_full" 2>/dev/null; sleep 1
    echo "启动 writer (高速写入 ${WRITER_SPEED_KBPS}KB/s)..."
    nohup "$BIN_DIR/pipe_buf_full" writer "$PIPE_SIZE_KB" "$WRITER_SPEED_KBPS" > /tmp/pipe_writer.log 2>&1 &
    PID_W=$!
    echo "Writer PID: $PID_W"
    echo "启动 reader (低速读取)..."
    nohup "$BIN_DIR/pipe_buf_full" reader 1 > /tmp/pipe_reader.log 2>&1 &
    PID_R=$!
    echo "Reader PID: $PID_R"
    sleep 4
    echo ""
    echo "=== 注入后状态 ==="
    echo "Writer PID $PID_W 状态:"
    ps -o pid,stat,wchan,comm --pid $PID_W 2>/dev/null | head -2
    echo "Reader PID $PID_R 状态:"
    ps -o pid,stat,wchan,comm --pid $PID_R 2>/dev/null | head -2
    echo ""
    echo "D 状态进程检查:"
    ps aux | grep pipe_buf_full | grep -v grep
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "检测到管道缓冲区满导致写阻塞：writer PID $PID_W 写入速度 ${WRITER_SPEED_KBPS}KB/s，管道缓冲区 ${PIPE_SIZE_KB}KB，reader PID $PID_R 读取过慢。writer 可能处于 D 状态（不可中断睡眠）。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== pipe_buf 状态 ==="
    echo "Writer:"
    ps aux | grep "pipe_buf_full.*writer" | grep -v grep || echo "  (未运行)"
    echo "Reader:"
    ps aux | grep "pipe_buf_full.*reader" | grep -v grep || echo "  (未运行)"
    echo ""
    echo "D 状态 writer:"
    ps aux | grep pipe_buf_full | grep " D" | grep -v grep || echo "  (无 D 状态)"
    ;;
  stop)
    echo "停止 pipe_buf 注入..."
    pkill -f "pipe_buf_full" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop] [pipe_size_kb] [writer_speed_kbps]"
    ;;
esac
