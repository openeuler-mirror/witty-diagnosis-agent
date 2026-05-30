#!/usr/bin/env bash
# =============================================================================
# 脚本：check_syscall.sh
# 用途：Syscall 热点快速检测脚本（可定时运行或按需排查）
# 使用：bash check_syscall.sh <pid> [duration]
# 示例：
#   bash check_syscall.sh 1234 10   # PID 1234，采集10秒
#   bash check_syscall.sh 1234      # PID 1234，默认5秒
# =============================================================================

set -euo pipefail

echo "=================================================================="
echo " Syscall 热点检测器"
echo " 时间: $(date)"
echo "=================================================================="

TARGET_PID="${1:-}"
DURATION="${2:-5}"

if [ -z "$TARGET_PID" ]; then
  echo "❌ 请指定 PID"
  echo "用法: bash check_syscall.sh <pid> [duration]"
  echo "示例: bash check_syscall.sh 1234 10"
  exit 1
fi

if ! kill -0 "$TARGET_PID" 2>/dev/null; then
  echo "❌ PID $TARGET_PID 不存在"
  exit 1
fi

echo "  目标 PID: $TARGET_PID"
echo "  进程名: $(cat /proc/$TARGET_PID/comm 2>/dev/null || echo 'N/A')"
echo "  采集时长: ${DURATION}s"
echo ""

# 1. 当前状态快照
echo "------------------------------------------------------------------"
echo " 当前状态"
echo "------------------------------------------------------------------"
echo "  状态: $(cat /proc/$TARGET_PID/status 2>/dev/null | grep "^State" | awk '{print $2, $3}' || echo 'N/A')"
echo "  当前 syscall: $(cat /proc/$TARGET_PID/syscall 2>/dev/null || echo 'N/A')"
echo "  内核 wchan: $(cat /proc/$TARGET_PID/wchan 2>/dev/null || echo 'N/A')"
echo "  FD 数: $(ls /proc/$TARGET_PID/fd 2>/dev/null | wc -l || echo 'N/A')"
echo ""

# 2. strace 快速采样
echo "------------------------------------------------------------------"
echo " strace 汇总统计（${DURATION}s）"
echo "------------------------------------------------------------------"

if command -v strace &>/dev/null; then
  timeout "${DURATION}" strace -c -p "${TARGET_PID}" 2>&1 || echo "  strace 失败（权限不足？）"
else
  echo "  strace 不可用"
fi

echo ""

# 3. 错误码统计
echo "------------------------------------------------------------------"
echo " 失败 syscall（${DURATION}s）"
echo "------------------------------------------------------------------"
if command -v strace &>/dev/null; then
  timeout "${DURATION}" strace -e status=failed -p "${TARGET_PID}" 2>&1 | \
    sort | uniq -c | sort -rn | head -10 || echo "  无失败 syscall"
else
  echo "  strace 不可用"
fi

echo ""

# 4. 综合判定
echo "------------------------------------------------------------------"
echo " 判定结果"
echo "------------------------------------------------------------------"

# 读取状态
CURRENT_SYSCALL=$(cat /proc/$TARGET_PID/syscall 2>/dev/null | awk '{print $1}' || echo "?")

# 检查是否在 D 状态
PROC_STATE=$(cat /proc/$TARGET_PID/status 2>/dev/null | grep "^State" | awk '{print $2}' || echo "?")

case "$PROC_STATE" in
  D)
    echo "  🔴 进程处于 D 状态（不可中断睡眠）"
    echo "  内核栈: $(cat /proc/$TARGET_PID/stack 2>/dev/null | head -5)"
    echo "  建议: 检查 IO 状态和对应设备"
    ;;
  S)
    echo "  🟡 进程处于 S 状态（可中断睡眠）"
    echo "  当前 syscall 编号: ${CURRENT_SYSCALL}"
    echo "  建议: strace -p ${TARGET_PID} 确认等待的具体 syscall"
    ;;
  R)
    echo "  🟢 进程处于 R 状态（运行中）"
    echo "  建议: 如果 CPU 高，用 strace -c 查看热点 syscall"
    ;;
  *)
    echo "  进程状态: ${PROC_STATE}"
    ;;
esac

echo ""
echo "------------------------------------------------------------------"
echo " 检测完成。时间: $(date)"
echo "=================================================================="
