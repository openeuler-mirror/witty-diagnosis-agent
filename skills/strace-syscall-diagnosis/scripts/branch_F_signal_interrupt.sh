#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_F_signal_interrupt.sh
# 用途：信号/中断模式诊断 — 双轨分析
# 使用：bash branch_F_signal_interrupt.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支F：信号/中断模式 —— 双轨分析"
echo "=================================================================="

BASELINE_TARGET="${OUT_DIR}/process_status.txt"
STDERR="${OUT_DIR}/strace_all.txt"
TARGET_PID=$(grep "^Pid:" "$BASELINE_TARGET" 2>/dev/null | awk '{print $2}' || echo "")

# --------------------------------------------------------------------------
# T1 - EINTR 统计
# --------------------------------------------------------------------------
echo ""
echo "【T1】EINTR（被信号中断的 syscall）统计"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  EINTR_COUNT=$(grep -c "EINTR" "$STDERR" 2>/dev/null || echo 0)
  echo "  EINTR 总次数: ${EINTR_COUNT}"

  if [ "$EINTR_COUNT" -gt 0 ]; then
    echo ""
    echo "  EINTR 分布:"
    grep "EINTR" "$STDERR" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10
    echo ""
    echo "  ⚠ EINTR 频繁出现说明:"
    echo "    · 进程频繁收到信号"
    echo "    · syscall 被中断后未自动重启（可能缺 SA_RESTART）"
    echo "    · 需要检查 sigaction() 设置"
  else
    echo "  ✅ 无 EINTR 记录"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# T2 - 信号发送分析
# --------------------------------------------------------------------------
echo ""
echo "【T2】strace 信号追踪（5s）"
echo "------------------------------------------------------------------"
if command -v strace &>/dev/null && [ -n "$TARGET_PID" ]; then
  echo "  追踪信号传递..."
  timeout 5 strace -e trace=kill,tkill,tgkill,sigaction,signal -p "${TARGET_PID}" 2>&1 | head -30 || echo "  (无信号相关 syscall)"
fi

echo ""

# --------------------------------------------------------------------------
# T3 - /proc 状态
# --------------------------------------------------------------------------
echo ""
echo "【T3】进程信号状态"
echo "------------------------------------------------------------------"
if [ -n "$TARGET_PID" ] && [ -d "/proc/${TARGET_PID}" ]; then
  echo "  Pending 信号:"
  echo "    $(cat /proc/${TARGET_PID}/status 2>/dev/null | grep "SigPnd" || echo "N/A")"
  echo "    $(cat /proc/${TARGET_PID}/status 2>/dev/null | grep "ShdPnd" || echo "N/A")"
  echo ""
  echo "  信号处理:"
  echo "    $(cat /proc/${TARGET_PID}/status 2>/dev/null | grep "SigCgt" || echo "N/A")"
  echo "    $(cat /proc/${TARGET_PID}/status 2>/dev/null | grep "SigIgn" || echo "N/A")"
fi

echo ""

echo "【T4】调用轨迹轨道结论"
echo "------------------------------------------------------------------"
{
  echo "  EINTR 次数: ${EINTR_COUNT:-0}"
  echo "  调用轨迹归因假设: 基于 EINTR 频率和信号分布"
} | tee -a "${OUT_DIR}/branch_F_metrics.txt"

# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道"
echo "=================================================================="
cat << 'SRCGUIDE'
  EINTR 的含义:
    慢速 syscall（read/write/connect/accept/poll/epoll_wait 等）
    在等待期间收到信号 → 内核返回 EINTR
    
  处理方式:
    ① 自动重启: sigaction 设置 SA_RESTART 标志
       → 内核自动重发被中断的 syscall，应用无感知
    ② 手动重试: 应用代码检查 EINTR 后手动重试
    ③ 不管: 当成错误处理（通常是 bug）

  信号模式识别:
    · SIGPIPE → write 到已关闭的 socket/pipe（检查 EPIPE）
    · SIGTERM/SIGINT → 优雅关闭触发
    · SIGALRM → 定时器超时
    · SIGCHLD → 子进程退出（大量子进程时可能风暴）

  排查方向:
    1. 谁在发信号: strace -e trace=kill -p 发送者_PID
    2. 信号处理: cat /proc/<PID>/status | grep SigCgt
    3. SA_RESTART: gdb -p <PID> 查看 sigaction 结构
    4. tkill/tgkill: 检查是否多线程间互相发信号
SRCGUIDE

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: 信号/中断异常
  处理建议:
    · EINTR 频繁 + 无 SA_RESTART → 添加 sigaction(SA_RESTART)
    · SIGPIPE 频繁 → 检查 EPIPE 处理逻辑
    · 信号风暴 → 定位信号来源（strace -e kill）
    
    常见修复:
      /* C 代码: 添加 SA_RESTART */
      struct sigaction sa;
      sa.sa_flags = SA_RESTART;
      sigaction(SIGUSR1, &sa, NULL);
    
    【验证】
      - strace 中 EINTR 次数显著下降
CONCLUSION
