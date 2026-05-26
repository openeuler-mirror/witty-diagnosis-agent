#!/bin/bash
# ============================================================
# inject_uds_backlog.sh — Fault A: UDS Listen Backlog 满
# 故障: Unix Domain Socket listen backlog 被耗尽，后续连接被拒
# 对应 skill 分支: branch_A_uds_backlog.sh
# ============================================================
BIN_DIR="$HOME/unix-pipe-test-lab/bin"
ACTION="${1:-run}"
BACKLOG="${2:-2}"
CLIENTS="${3:-10}"

case "$ACTION" in
  run)
    echo "=== UDS Listen Backlog 满 (Fault A) ==="
    pkill -f "uds_backlog" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/uds_backlog" "$BACKLOG" "$CLIENTS" > /tmp/uds_backlog.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 3
    ss -xl | head -20
    echo ""
    echo "=== Recv-Q 检查 ==="
    ss -x | awk '{print $2}' | sort | uniq -c | sort -rn
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "检测到 UDS listen backlog 满：PID $PID，backlog=$BACKLOG，client=$CLIENTS，ss -xl
显示大量连接处于 Recv-Q 堆积状态，新连接无法建立。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== UDS backlog 状态 ==="
    pgrep -f "uds_backlog" && echo "进程运行中" || echo "进程未运行"
    echo "UDS 监听连接:"
    ss -xl 2>/dev/null | grep -c "test_backlog" || echo "  (无匹配)"
    ;;
  stop)
    echo "停止 UDS backlog 注入..."
    pkill -f "uds_backlog" 2>/dev/null; sleep 1; echo "已停止"
    rm -f /tmp/test_backlog* 2>/dev/null
    ;;
  *)
    echo "用法: $0 [run|status|stop] [backlog] [clients]"
    ;;
esac
