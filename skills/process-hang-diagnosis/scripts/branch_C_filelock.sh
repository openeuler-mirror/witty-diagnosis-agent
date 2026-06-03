#!/bin/bash
#
# 分支 C: 文件锁竞争诊断
# 场景: 进程在等待文件锁 (fcntl/flock)
# OS 特征: /proc/locks 有本进程的锁等待
#
# 用法: bash ./scripts/branch_C_filelock.sh <pid> [work_dir]

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
echo "===== 分支 C: 文件锁竞争诊断 ====="
mkdir -p "$WORK_DIR/sys"

# O1: 确认进程 fd 中的锁文件
echo ""
echo "--- O1: 进程文件描述符 ---"
ls -la /proc/$PID/fd/ 2>/dev/null || echo "(无法读取 fd)"
echo ""
echo "排查是否有 .lock 或锁文件 fd"

# O2: 检查 /proc/locks 中与进程相关的锁
echo ""
echo "--- O2: /proc/locks 匹配分析 ---"
PROC_LOCKS="$WORK_DIR/sys/locks"
cat /proc/locks 2>/dev/null > "$PROC_LOCKS"

# 找到本进程的锁条目
echo "本进程相关的锁:"
grep " $PID " "$PROC_LOCKS" 2>/dev/null || echo "(本进程没有持有或等待文件锁)"

# 检查是否有锁正在被本进程等待
echo ""
echo "所有文件锁列表:"
cat "$PROC_LOCKS" 2>/dev/null || echo "(无法读取 /proc/locks)"

# O3: 锁持有者活性检查
echo ""
echo "--- O3: 锁持有者活性检查 ---"
# 从 /proc/locks 提取所有持有者 PID
lsof -p "$PID" 2>/dev/null | grep -E "REG.*\.lock" || true
echo ""
echo "检查锁持有者进程是否存活："
awk '{print $5}' "$PROC_LOCKS" 2>/dev/null | grep -E '^[0-9]+$' | sort -u | while read -r holder; do
    if kill -0 "$holder" 2>/dev/null; then
        echo "  持有者 PID $holder — 存活 (comm: $(cat /proc/$holder/comm 2>/dev/null || echo '?'))"
    else
        echo "  持有者 PID $holder — 已退出（文件锁应自动释放，确认是否 POSIX 锁）"
    fi
done

# G4: lslocks 检查
echo ""
echo "--- G4: lslocks 工具 ---"
if command -v lslocks &>/dev/null; then
    lslocks -p "$PID" 2>/dev/null || echo "(lslocks 无输出)"
else
    echo "[SKIP] lslocks 未安装 (util-linux 包)"
fi

# 输出摘要
echo ""
echo "===== 分支 C 诊断摘要 ====="
echo "进程 $PID 的文件锁状态见上。"
echo "核心判断:"
echo "  本进程在等待文件锁还是持有锁？确认 /proc/locks 中的相关条目"
echo "  锁持有者是否存活？进程退出后 POSIX 锁会自动释放"
