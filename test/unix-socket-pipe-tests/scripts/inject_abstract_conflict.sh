#!/bin/bash
# ============================================================
# inject_abstract_conflict.sh — Fault B: Abstract Socket 冲突
# 故障: 两个进程绑定同一 abstract socket 地址 @uds_test，地址冲突
# 对应 skill 分支: branch_B_abstract_conflict.sh
# ============================================================
BIN_DIR="$HOME/unix-pipe-test-lab/bin"
ACTION="${1:-run}"
ADDR="${2:-@uds_test}"

case "$ACTION" in
  run)
    echo "=== Abstract Socket 地址冲突 (Fault B) ==="
    pkill -f "abstract_conflict" 2>/dev/null; sleep 1
    echo "启动第一个进程绑定 $ADDR ..."
    nohup "$BIN_DIR/abstract_conflict" bind "$ADDR" > /tmp/abstract_srv1.log 2>&1 &
    PID1=$!
    echo "PID1: $PID1"
    sleep 1
    echo "启动第二个进程尝试绑定相同地址 $ADDR ..."
    nohup "$BIN_DIR/abstract_conflict" bind "$ADDR" > /tmp/abstract_srv2.log 2>&1 &
    PID2=$!
    echo "PID2: $PID2"
    sleep 2
    echo ""
    echo "=== 注入后状态 ==="
    echo "PID1 存活: $(kill -0 $PID1 2>/dev/null && echo 是 || echo 否)"
    echo "PID2 存活: $(kill -0 $PID2 2>/dev/null && echo 是 || echo 否)"
    echo "UDS abstract 连接:"
    ss -xl | grep -E "@${ADDR#@}" || echo "  (无匹配)"
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "检测到 Unix Domain Socket abstract 地址冲突：第二个进程 PID $PID2 尝试绑定已占用的 $ADDR 失败。ss -xl 未显示第二个监听实例。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== abstract 冲突状态 ==="
    PID1=$(pgrep -f "abstract_conflict" | head -1)
    PID2=$(pgrep -f "abstract_conflict" | tail -1)
    [ -n "$PID1" ] && echo "进程1 PID: $PID1" || echo "进程1: 未运行"
    [ -n "$PID2" ] && echo "进程2 PID: $PID2" || echo "进程2: 未运行"
    echo "Abstract socket 连接数: $(ss -xl 2>/dev/null | grep -c "@${ADDR#@}" || true)"
    ;;
  stop)
    echo "停止 abstract 冲突注入..."
    pkill -f "abstract_conflict" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop] [addr]"
    ;;
esac
