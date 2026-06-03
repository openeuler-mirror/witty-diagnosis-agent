#!/bin/bash
#
# 分支 F: D 状态阻塞诊断
# 场景: 进程在 D 状态（TASK_UNINTERRUPTIBLE）阻塞
# OS 特征: State=D, 不可中断等待 IO
#
# 用法: bash ./scripts/branch_F_d_state.sh <pid> [work_dir]

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
echo "===== 分支 F: D 状态阻塞诊断 ====="
mkdir -p "$WORK_DIR/sys"

# O1: 确认 D 状态和 wchan
echo ""
echo "--- O1: D 状态确认 ---"
echo "State: $(cat /proc/$PID/status 2>/dev/null | grep "^State:" | awk '{print $2}')"
echo "wchan: $(cat /proc/$PID/wchan 2>/dev/null)"
echo ""
echo "内核栈:"
cat /proc/$PID/stack 2>/dev/null || echo "(unavailable)"

# O2: 检查 IO 相关指标
echo ""
echo "--- O2: IO 状态 ---"
cat /proc/$PID/io 2>/dev/null || echo "(unavailable)"

# O3: 全系统 D 状态进程
echo ""
echo "--- O3: 全系统 D 状态进程 ---"
ps -eo pid,state,wchan,comm --no-headers 2>/dev/null | awk '$2=="D" {print "  PID=" $1 " wchan=" $3 " comm=" $4}' || echo "(无 D 状态进程)"

# O4: 检查特定 IO 类型
echo ""
echo "--- O4: IO 阻塞类型识别 ---"
WCHAN=$(cat /proc/$PID/wchan 2>/dev/null)
case "$WCHAN" in
    *rpc*|*nfs*|*nfsd*)
        echo "  NFS 相关阻塞 — 检查 NFS 服务器可达性"
        mount | grep nfs
        ;;
    *lock_page*|*wait_on_page*)
        echo "  页缓存等待 — 内存/文件系统 IO 阻塞"
        ;;
    *blkdev*|*submit_bio*)
        echo "  块设备 IO 阻塞 — 检查磁盘健康状态"
        ;;
    *fuse*)
        echo "  FUSE 文件系统阻塞 — 检查 FUSE 守护进程状态"
        ps aux | grep fuse
        ;;
    *ext4*|*xfs*|*btrfs*)
        echo "  文件系统 IO 阻塞 — 文件系统级操作等待"
        ;;
    *)
        echo "  wchan=$WCHAN — 请根据内核函数名判断 IO 类型"
        ;;
esac

# O5: sysrq-w 采集（需 root）
echo ""
echo "--- O5: sysrq-w D 状态 trace（需 root）---"
if [ "$(id -u)" = "0" ]; then
    echo "执行 sysrq-w ..."
    echo w > /proc/sysrq-trigger 2>/dev/null || echo "[WARN] sysrq 不可用"
    sleep 1
    dmesg | tail -60 | tee "$WORK_DIR/sys/sysrq-trigger" | grep -A5 "PID.*$PID" || echo "(当前进程不在最近的 sysrq-w 输出中)"
else
    echo "[SKIP] 需要 root 权限执行 sysrq-w"
fi

# 输出摘要
echo ""
echo "===== 分支 F 诊断摘要 ====="
echo "进程 $PID 处于 D 状态 (TASK_UNINTERRUPTIBLE)"
echo "wchan: $(cat /proc/$PID/wchan 2>/dev/null)"
echo ""
echo "D 状态特性:"
echo "  - 进程在内核中执行不可中断操作（通常为 IO）"
echo "  - kill -9 无效（进程在内核态，无法响应信号）"
echo "  - 只能等待内核 IO 完成或重启恢复"
echo ""
echo "常见原因:"
echo "  - 磁盘/NFS 故障导致 IO 挂起"
echo "  - FUSE 守护进程异常"
echo "  - 文件系统元数据操作阻塞"
echo "  - 内存回收（kswapd）等待 IO"
