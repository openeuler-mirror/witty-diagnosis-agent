#!/bin/bash
# ============================================================
# inject_socket_perms.sh — Fault D: Socket 文件权限错误
# 故障: server 创建 UDS socket 文件设置了错误权限
#       (默认 0000)，导致 client 无法连接
# 对应 skill 分支: branch_D_socket_perms.sh
# ============================================================
BIN_DIR="$HOME/unix-pipe-test-lab/bin"
ACTION="${1:-run}"
PERM="${2:-0000}"

case "$ACTION" in
  run)
    echo "=== Socket 文件权限错误 (Fault D) ==="
    pkill -f "socket_perms" 2>/dev/null; sleep 1
    echo "启动 server 绑定 /tmp/test_uds_perms 权限 $PERM ..."
    nohup "$BIN_DIR/socket_perms" "$PERM" > /tmp/socket_perms.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 2
    echo ""
    echo "=== 注入后状态 ==="
    ls -la /tmp/test_uds_perms 2>/dev/null || echo "(socket 文件不存在)"
    echo ""
    stat -c "%a %A %U:%G" /tmp/test_uds_perms 2>/dev/null || true
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "检测到 UDS socket 文件权限异常：/tmp/test_uds_perms 权限为 $PERM（$(stat -c '%a' /tmp/test_uds_perms 2>/dev/null)），导致 client 无法连接。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== socket 权限状态 ==="
    ps aux | grep socket_perms | grep -v grep
    ls -la /tmp/test_uds_perms 2>/dev/null || echo "(socket 文件不存在)"
    echo "权限: $(stat -c '%a' /tmp/test_uds_perms 2>/dev/null || echo N/A)"
    ;;
  stop)
    echo "停止 socket 权限注入..."
    pkill -f "socket_perms" 2>/dev/null; sleep 1; echo "已停止"
    rm -f /tmp/test_uds_* 2>/dev/null
    ;;
  *)
    echo "用法: $0 [run|status|stop] [perm]"
    ;;
esac
