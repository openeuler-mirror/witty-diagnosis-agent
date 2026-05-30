#!/usr/bin/env bash
# =============================================================================
# 脚本：01_baseline_info.sh
# 用途：Syscall 诊断 基线信息收集与分支推荐
# 使用：bash 01_baseline_info.sh [pid|command] [duration]
# 参数：
#   $1  PID 或命令名（默认当前 shell 的 PID）
#   $2  采集时长（秒，默认 10）
# =============================================================================

set -euo pipefail

TARGET="${1:-$$}"
DURATION="${2:-10}"
OUT_DIR="/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"

echo "=================================================================="
echo " Syscall 诊断 — 基线信息收集"
echo " 目标: ${TARGET}"
echo " 时长: ${DURATION}s"
echo " 输出: ${OUT_DIR}"
echo "=================================================================="

# 解析目标
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  TARGET_TYPE="pid"
  TARGET_PID=$TARGET
  PROC_NAME=$(cat /proc/$TARGET/comm 2>/dev/null || echo "unknown")
  echo "  模式: attach PID=$TARGET ($PROC_NAME)"
else
  TARGET_TYPE="command"
  TARGET_CMD=$TARGET
  echo "  模式: 启动命令: $TARGET"
fi

# 1. 进程基础状态
echo ""
echo "▶ [1/8] 进程基础状态 ..."
{
  if [ "$TARGET_TYPE" = "pid" ]; then
    echo "=== /proc/${TARGET_PID}/status ==="
    cat /proc/${TARGET_PID}/status 2>/dev/null || echo "PID not found"
    echo ""
    echo "=== /proc/${TARGET_PID}/syscall ==="
    cat /proc/${TARGET_PID}/syscall 2>/dev/null || echo "N/A"
    echo ""
    echo "=== /proc/${TARGET_PID}/wchan ==="
    cat /proc/${TARGET_PID}/wchan 2>/dev/null || echo "N/A"
    echo ""
    echo "=== /proc/${TARGET_PID}/stack (内核栈) ==="
    cat /proc/${TARGET_PID}/stack 2>/dev/null || echo "N/A"
    echo ""
    echo "=== FD 数量 ==="
    ls /proc/${TARGET_PID}/fd 2>/dev/null | wc -l || echo "N/A"
    echo ""
    echo "=== FD 列表 ==="
    ls -la /proc/${TARGET_PID}/fd 2>/dev/null | head -30
  fi
} > "${OUT_DIR}/process_status.txt" 2>/dev/null
echo "  -> process_status.txt"

# 2. 系统资源和限制
echo ""
echo "▶ [2/8] 系统资源和限制 ..."
{
  echo "=== ulimit -a ==="
  ulimit -a 2>/dev/null || true
  echo ""
  echo "=== sysctl (关键参数) ==="
  sysctl fs.file-max fs.nr_open kernel.pid_max kernel.threads-max \
         net.core.somaxconn vm.max_map_count 2>/dev/null || true
} > "${OUT_DIR}/system_limits.txt" 2>/dev/null
echo "  -> system_limits.txt"

# 3. strace 汇总统计
echo ""
echo "▶ [3/8] strace 汇总统计 (${DURATION}s) ..."
{
  if command -v strace &>/dev/null; then
    if [ "$TARGET_TYPE" = "pid" ]; then
      timeout "${DURATION}" strace -c -p "${TARGET_PID}" 2>&1 || true
    else
      timeout "${DURATION}" strace -c ${TARGET_CMD} 2>&1 || true
    fi
  else
    echo "strace 不可用，请安装 strace"
  fi
} > "${OUT_DIR}/strace_summary.txt" 2>/dev/null
echo "  -> strace_summary.txt"

# 4. strace 仅失败 syscall
echo ""
echo "▶ [4/8] strace 失败 syscall (${DURATION}s) ..."
{
  if command -v strace &>/dev/null; then
    if [ "$TARGET_TYPE" = "pid" ]; then
      timeout "${DURATION}" strace -e status=failed -p "${TARGET_PID}" 2>&1 | \
        sort | uniq -c | sort -rn | head -20 || true
    fi
  fi
} > "${OUT_DIR}/strace_errors.txt" 2>/dev/null
echo "  -> strace_errors.txt"

# 5. strace 慢 syscall (带耗时)
echo ""
echo "▶ [5/8] strace 慢 syscall Top (${DURATION}s) ..."
{
  if command -v strace &>/dev/null; then
    if [ "$TARGET_TYPE" = "pid" ]; then
      timeout "${DURATION}" strace -T -r -p "${TARGET_PID}" 2>&1 | \
        head -500 > "${OUT_DIR}/strace_all.txt" || true
    fi
    echo "完整 trace 保存在 strace_all.txt"
  fi
} > /dev/null 2>&1
echo "  -> strace_all.txt"

# 6. 检查 EAGAIN 频率
echo ""
echo "▶ [6/8] EAGAIN 频率分析 ..."
{
  if [ -f "${OUT_DIR}/strace_all.txt" ]; then
    EAGAIN_COUNT=$(grep -c "EAGAIN" "${OUT_DIR}/strace_all.txt" 2>/dev/null || echo 0)
    TOTAL_CALLS=$(wc -l < "${OUT_DIR}/strace_all.txt" 2>/dev/null || echo 0)
    echo "  总 syscall 数: ${TOTAL_CALLS}"
    echo "  EAGAIN 次数: ${EAGAIN_COUNT}"
    if [ "$TOTAL_CALLS" -gt 0 ]; then
      PCT=$(echo "scale=2; $EAGAIN_COUNT * 100 / $TOTAL_CALLS" | bc 2>/dev/null || echo 0)
      echo "  EAGAIN 占比: ${PCT}%"
    fi

    # 统计各 errno 频率
    echo ""
    echo "  === 错误码统计 ==="
    grep -oP "(E[A-Z_]+)" "${OUT_DIR}/strace_all.txt" 2>/dev/null | \
      sort | uniq -c | sort -rn | head -10 || true
  fi
} > "${OUT_DIR}/eagain_analysis.txt" 2>/dev/null
echo "  -> eagain_analysis.txt"

# 7. FD 数量（如有 PID）
echo ""
echo "▶ [7/8] FD 数量采样 ..."
{
  if [ "$TARGET_TYPE" = "pid" ] && [ -d "/proc/${TARGET_PID}" ]; then
    echo "  FD 数量: $(ls /proc/${TARGET_PID}/fd 2>/dev/null | wc -l)"
    echo "  FD 上限: $(cat /proc/${TARGET_PID}/limits 2>/dev/null | grep "open files" | awk '{print $4}' || echo "N/A")"
  fi
} > "${OUT_DIR}/fd_count.txt" 2>/dev/null
echo "  -> fd_count.txt"

# 8. 分支决策
echo ""
echo "▶ [8/8] 分支推荐 ..."
echo "------------------------------------------------------------------"

{
  echo "=================================================================="
  echo " Syscall 诊断 — 分支推荐"
  echo "=================================================================="
  echo ""

  # 获取关键指标
  SUMMARY="${OUT_DIR}/strace_summary.txt"
  ERRORS="${OUT_DIR}/strace_errors.txt"
  STDERR="${OUT_DIR}/strace_all.txt"
  FD_COUNT="${OUT_DIR}/fd_count.txt"

  # 检查错误码模式
  ERROR_PATTERNS=$(cat "${ERRORS}" 2>/dev/null || true)
  ALL_STDERR=$(cat "${STDERR}" 2>/dev/null || true)
  HAS_EACCES=false; HAS_ENOENT=false; HAS_EAGAIN=false; HAS_ENOMEM=false
  echo "$ERROR_PATTERNS" | grep -qi "EACCES\|EPERM" && HAS_EACCES=true
  echo "$ERROR_PATTERNS" | grep -qi "ENOENT" && HAS_ENOENT=true
  echo "$ERROR_PATTERNS" | grep -qi "EAGAIN\|EWOULDBLOCK" && HAS_EAGAIN=true
  echo "$ERROR_PATTERNS" | grep -qi "ENOMEM" && HAS_ENOMEM=true

  # 检查慢 syscall（从 strace_all 或 -c 输出）
  SLOW_SYSCALLS=""
  [ -f "${STDERR}" ] && SLOW_SYSCALLS=$(grep -E "futex|epoll_wait" "${STDERR}" | head -10 || true)
  HAS_SLOW_FUTEX=false
  echo "$SLOW_SYSCALLS" | grep -q "futex" && HAS_SLOW_FUTEX=true

  # 分支 D: FD泄漏检测
  HAS_FD_LEAK=false
  FD_NUM=$(cat "${FD_COUNT}" 2>/dev/null | grep -oP '\d+' | head -1 || echo 0)
  [ "$FD_NUM" -gt 1000 ] 2>/dev/null && HAS_FD_LEAK=true
  echo "$ALL_STDERR" | grep -qi "EMFILE\|ENFILE" && HAS_FD_LEAK=true
  echo "$ALL_STDERR" | grep -qi "munmap" || true  # just check for munmap presence

  # 分支 E: 网络错误检测
  HAS_NET_ERR=false
  echo "$ALL_STDERR" | grep -qi "ECONNREFUSED\|ETIMEDOUT\|ECONNRESET\|EPIPE\|EADDRINUSE\|EHOSTUNREACH\|ENETUNREACH" && HAS_NET_ERR=true

  # 分支 F: 信号中断检测
  HAS_EINTR=false
  echo "$ALL_STDERR" | grep -qi "EINTR" && HAS_EINTR=true

  # 分支 G: 生命周期异常
  HAS_LIFECYCLE=false
  CLONE_COUNT=$(echo "$ALL_STDERR" | grep -cE "^clone\b|^fork\b" 2>/dev/null || echo 0)
  [ "$CLONE_COUNT" -gt 50 ] 2>/dev/null && HAS_LIFECYCLE=true
  echo "$ALL_STDERR" | grep -qi "execve.*-1" && HAS_LIFECYCLE=true

  echo "【检测结果】"
  echo "  EACCES/EPERM: ${HAS_EACCES}"
  echo "  ENOENT:       ${HAS_ENOENT}"
  echo "  EAGAIN:       ${HAS_EAGAIN}"
  echo "  ENOMEM:       ${HAS_ENOMEM}"
  echo "  slow futex:   ${HAS_SLOW_FUTEX}"
  echo "  FD 数量:      ${FD_NUM}"
  echo "  FD 泄漏:      ${HAS_FD_LEAK}"
  echo "  网络错误:     ${HAS_NET_ERR}"
  echo "  EINTR:        ${HAS_EINTR}"
  echo "  生命周期:     ${HAS_LIFECYCLE} (fork/clone=${CLONE_COUNT})"
  echo ""

  echo "【分支推荐】"
  MATCHED=0

  if $HAS_EACCES || $HAS_ENOENT || $HAS_ENOMEM; then
    echo "  ✓ 分支A: 错误码模式识别"
    echo "     → bash scripts/branch_A_syscall_error.sh ${OUT_DIR}"
    MATCHED=1
  fi

  if $HAS_SLOW_FUTEX; then
    echo "  ✓ 分支B: 慢 Syscall 定位"
    echo "     → bash scripts/branch_B_slow_syscall.sh ${OUT_DIR}"
    MATCHED=1
  fi

  if $HAS_EAGAIN; then
    echo "  ✓ 分支A: 忙等检测 (EAGAIN 模式)"
    echo "  ✓ 分支B: 慢 Syscall 定位 (EAGAIN 循环)"
    echo "     → 建议同时执行 branch_A + branch_B"
    MATCHED=1
  fi

  if $HAS_FD_LEAK; then
    echo "  ✓ 分支D: FD/资源泄漏"
    echo "     → bash scripts/branch_D_fd_leak.sh ${OUT_DIR}"
    MATCHED=1
  fi

  if $HAS_NET_ERR; then
    echo "  ✓ 分支E: 网络 Syscall 异常"
    echo "     → bash scripts/branch_E_network_syscall.sh ${OUT_DIR}"
    MATCHED=1
  fi

  if $HAS_EINTR; then
    echo "  ✓ 分支F: 信号/中断模式"
    echo "     → bash scripts/branch_F_signal_interrupt.sh ${OUT_DIR}"
    MATCHED=1
  fi

  if $HAS_LIFECYCLE; then
    echo "  ✓ 分支G: 进程生命周期异常"
    echo "     → bash scripts/branch_G_lifecycle.sh ${OUT_DIR}"
    MATCHED=1
  fi

  if [ "$MATCHED" -eq 0 ]; then
    echo "  未检测到明显异常"
    echo "  建议执行通用检查: bash scripts/check_syscall.sh ${OUT_DIR}"
  fi

  echo "=================================================================="
} > "${OUT_DIR}/branch_recommendation.txt" 2>/dev/null

cat "${OUT_DIR}/branch_recommendation.txt"
echo ""
echo "基线收集完成。输出目录: ${OUT_DIR}"
