#!/bin/bash
#
# 分支 D: 管道/Socket 阻塞读写诊断
# 场景: 进程在 pipe/socket 上阻塞读/写
# OS 特征: wchan=pipe_read/pipe_write/sock_*/tcp_*/unix_*
#
# 用法: bash ./scripts/branch_D_pipe_socket.sh <pid> [work_dir]

set -euo pipefail

# CMD_PREFIX: 命令执行前缀，容器诊断时设置为 "docker exec <容器名>"
# 示例: CMD_PREFIX="docker exec process-hang-branch-g" bash 01_baseline_info.sh 1
: "${CMD_PREFIX:=}"

# run() — 通过 CMD_PREFIX 执行命令
run() {
  if [ -n "$CMD_PREFIX" ]; then
    $CMD_PREFIX "$@"
  else
    "$@"
  fi
}


PID="${1:?Usage: $0 <pid> [work_dir]}"
WORK_DIR="${2:-./hang_diag_${PID}}"
echo "===== 分支 D: 管道/Socket 阻塞诊断 ====="
mkdir -p "$WORK_DIR/gdb_output"

# O1: 确认 OS 状态
echo ""
echo "--- O1: 确认阻塞点和 fd ---"
echo "wchan: $(cat /proc/$PID/wchan 2>/dev/null)"
echo "syscall: $(cat /proc/$PID/syscall 2>/dev/null || echo 'N/A')"

# O2: 列出所有 pipe/socket fd
echo ""
echo "--- O2: 管道和socket 文件描述符 ---"
pipe_count=0
socket_count=0
for f in /proc/$PID/fd/*; do
    fd=$(basename "$f")
    link=$(readlink "$f" 2>/dev/null || echo "?")
    case "$link" in
        pipe:*)
            echo "  FD $fd -> $link"
            pipe_count=$((pipe_count + 1))
            ;;
        socket:*)
            echo "  FD $fd -> $link"
            socket_count=$((socket_count + 1))
            ;;
    esac
done
echo "pipe fd 数: $pipe_count, socket fd 数: $socket_count"

# O3: 对每个 pipe 查找对端
echo ""
echo "--- O3: 管道对端定位 ---"
for f in /proc/$PID/fd/*; do
    link=$(readlink "$f" 2>/dev/null)
    if [[ $link == pipe:* ]]; then
        inode=$(echo "$link" | grep -oP '\[(\d+)\]' | grep -oP '\d+')
        echo ""
        echo "pipe fd $(basename $f) inode=$inode"
        echo -n "  对端: "
        find /proc/*/fd -lname "$link" 2>/dev/null | grep -v "/proc/$pid/" || echo "(未找到 — 对端可能已退出)"
    fi
done

# O4: Socket 状态检查
echo ""
echo "--- O4: Socket 状态 ---"
for f in /proc/$PID/fd/*; do
    link=$(readlink "$f" 2>/dev/null)
    if [[ $link == socket:* ]]; then
        inode=$(echo "$link" | grep -oP '\[(\d+)\]' | grep -oP '\d+')
        echo ""
        echo "socket fd $(basename $f) inode=$inode"
        # 检查 TCP socket 状态
        if [ -f /proc/net/tcp ]; then
            echo -n "  TCP 状态: "
            awk -v inode="$inode" '$10 == inode {print "st=" $4 " txq=" $5 " rxq=" $6}' /proc/net/tcp 2>/dev/null || echo "(无 tcp 匹配)"
        fi
        # 检查 Unix socket
        if [ -f /proc/net/unix ]; then
            echo -n "  Unix socket: "
            awk -v inode="$inode" '$7 == inode {print " Flags=" $5 " State=" $6}' /proc/net/unix 2>/dev/null || echo "(无 unix 匹配)"
        fi
    fi
done

# G4: gdb bt 确认
echo ""
echo "--- G4: 进程内省确认阻塞路径 ---"
if command -v gdb &>/dev/null && kill -0 "$PID" 2>/dev/null; then
    gdb --batch -nx -ex "bt" -p "$PID" 2>&1 | tee "$WORK_DIR/gdb_output/gdb_bt_pipe_socket.txt" || true
fi

# 输出摘要
echo ""
echo "===== 分支 D 诊断摘要 ====="
echo "管道/Socket 阻塞分析完成。"
echo "核心判断:"
echo "  管道读阻塞 → 写端是否存活？写端是否已关闭？"
echo "  管道写阻塞 → 读端是否存活？读缓冲区是否满？"
echo "  Socket 读阻塞 → 对端是否存活并发送数据？"
echo "  Socket 写阻塞 → 对端读取速度？send buffer 满？对端 window=0？"
