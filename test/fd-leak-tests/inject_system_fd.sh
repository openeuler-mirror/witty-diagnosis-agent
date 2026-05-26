#!/bin/bash
# ============================================================
# inject_system_fd.sh — Branch A: 系统级 FD 耗尽
# 故障: 子进程大量打开文件后不关闭，模拟系统 FD 水位上升
# 对应 skill 分支: branch_A_system_fd.sh
# 使用方式: bash inject_system_fd.sh [run|status|stop]
# ============================================================
BIN_DIR="$HOME/fd-leak-test-lab/bin"
ACTION="${1:-run}"

case "$ACTION" in
  run)
    echo "=== 系统级 FD 耗尽 (Branch A) ==="
    echo "启动 leak_system_fd 3 100 (3子进程各100FD)..."
    pkill -f "leak_system_fd" 2>/dev/null; sleep 1
    nohup "$BIN_DIR/leak_system_fd" 3 100 > /tmp/leak_sysfd.log 2>&1 &
    PID=$!
    echo "PID: $PID"
    sleep 3
    echo ""
    echo "=== 注入后状态 ==="
    cat /proc/sys/fs/file-nr | head -1
    echo ""
    ps aux | grep leak_system_fd | grep -v grep
    echo ""
    echo "=== 用于 Xuanyuan 新会话的 Prompt ==="
    echo "------------------------"
    echo "我的 Linux 服务器出现系统文件描述符泄漏。file-nr 显示使用量偏高。发现多个子进程各持有大量 FD，全部指向 /tmp/sysleak_* 文件。请全链路诊断定位根因。"
    echo ""
    echo "SSH: 127.0.0.1 / wyh"
    echo "------------------------"
    ;;
  status)
    echo "=== system_fd 泄漏状态 ==="
    ps aux | grep leak_system_fd | grep -v grep
    echo "file-nr: $(cat /proc/sys/fs/file-nr | head -1)"
    ;;
  stop)
    echo "停止 system_fd 泄漏..."
    pkill -f "leak_system_fd" 2>/dev/null; sleep 1; echo "已停止"
    ;;
  *)
    echo "用法: $0 [run|status|stop]"
    ;;
esac
